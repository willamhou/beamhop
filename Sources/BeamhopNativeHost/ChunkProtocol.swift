import Foundation

let bridgeProtocolVersion = 1
let browserToHostFrameLimit = 64 * 1024
let hostToBrowserFrameLimit = 1024 * 1024
let hostRawChunkSize = 700 * 1024
let reassemblyTimeout: TimeInterval = 15
let maximumBrowserLogicalBytes = 8 * 1024 * 1024
let maximumBrowserChunks = 256
let maximumConcurrentBrowserTransfers = 8

func fnv1a(_ data: Data) -> String {
    var hash: UInt32 = 0x811c9dc5
    for byte in data {
        hash ^= UInt32(byte)
        hash = hash &* 0x01000193
    }
    return String(format: "%08x", hash)
}

func controlMessage(_ type: String, _ fields: [String: Any] = [:]) -> [String: Any] {
    var result = fields
    result["protocolVersion"] = bridgeProtocolVersion
    result["type"] = type
    return result
}

struct ReassembledMessage {
    let transferID: String
    let requestID: String?
    let data: Data
}

enum AssemblyResult {
    case partial(received: Int, total: Int)
    case complete(ReassembledMessage)
    case failure(code: String, message: String)
}

private final class IncomingTransfer {
    let requestID: String?
    let total: Int
    let byteLength: Int
    let checksum: String
    var parts: [Int: Data] = [:]
    var receivedBytes = 0
    var updatedAt = Date()

    init(requestID: String?, total: Int, byteLength: Int, checksum: String) {
        self.requestID = requestID
        self.total = total
        self.byteLength = byteLength
        self.checksum = checksum
    }
}

final class ChunkAssembler {
    private let lock = NSLock()
    private var transfers: [String: IncomingTransfer] = [:]

    func accept(_ chunk: [String: Any]) -> AssemblyResult {
        lock.lock()
        defer { lock.unlock() }
        guard (chunk["protocolVersion"] as? Int) == bridgeProtocolVersion,
              (chunk["type"] as? String) == "chunk",
              let transferID = chunk["transferId"] as? String,
              let index = chunk["index"] as? Int,
              let total = chunk["total"] as? Int,
              let byteLength = chunk["byteLength"] as? Int,
              let checksum = chunk["checksum"] as? String,
              (chunk["encoding"] as? String) == "base64",
              let encoded = chunk["payload"] as? String,
              total > 0, total <= maximumBrowserChunks,
              index >= 0, index < total,
              byteLength >= 0, byteLength <= maximumBrowserLogicalBytes,
              encoded.utf8.count <= 60 * 1024 else {
            return .failure(code: "INVALID_CHUNK", message: "Chunk envelope is incomplete or invalid")
        }
        guard let part = Data(base64Encoded: encoded) else {
            transfers.removeValue(forKey: transferID)
            return .failure(code: "INVALID_BASE64", message: "Chunk payload is not valid base64")
        }

        let requestID = chunk["requestId"] as? String
        let transfer: IncomingTransfer
        if let current = transfers[transferID] {
            guard current.total == total,
                  current.byteLength == byteLength,
                  current.checksum == checksum else {
                transfers.removeValue(forKey: transferID)
                return .failure(code: "CHUNK_METADATA_MISMATCH", message: "Transfer metadata changed between chunks")
            }
            transfer = current
        } else {
            guard transfers.count < maximumConcurrentBrowserTransfers else {
                return .failure(code: "TOO_MANY_TRANSFERS", message: "Too many concurrent browser transfers")
            }
            transfer = IncomingTransfer(requestID: requestID, total: total, byteLength: byteLength, checksum: checksum)
            transfers[transferID] = transfer
        }

        let previousSize = transfer.parts[index]?.count ?? 0
        let nextReceivedBytes = transfer.receivedBytes - previousSize + part.count
        guard nextReceivedBytes <= byteLength else {
            transfers.removeValue(forKey: transferID)
            return .failure(code: "BYTE_LENGTH_EXCEEDED", message: "Chunk bytes exceed the declared logical length")
        }
        transfer.parts[index] = part
        transfer.receivedBytes = nextReceivedBytes
        transfer.updatedAt = Date()
        guard transfer.parts.count == total else {
            return .partial(received: transfer.parts.count, total: total)
        }

        var joined = Data()
        joined.reserveCapacity(byteLength)
        for partIndex in 0..<total {
            guard let item = transfer.parts[partIndex] else {
                transfers.removeValue(forKey: transferID)
                return .failure(code: "MISSING_CHUNK", message: "A chunk was missing at completion")
            }
            joined.append(item)
        }
        transfers.removeValue(forKey: transferID)
        guard joined.count == byteLength else {
            return .failure(code: "BYTE_LENGTH_MISMATCH", message: "Reassembled byte length does not match envelope")
        }
        guard fnv1a(joined) == checksum else {
            return .failure(code: "CHECKSUM_MISMATCH", message: "Reassembled checksum does not match envelope")
        }
        guard (try? JSONSerialization.jsonObject(with: joined)) != nil else {
            return .failure(code: "INVALID_LOGICAL_MESSAGE", message: "Reassembled payload is not JSON")
        }
        return .complete(ReassembledMessage(transferID: transferID, requestID: requestID, data: joined))
    }

    func removeExpired(now: Date = Date()) -> [(transferID: String, requestID: String?)] {
        lock.lock()
        defer { lock.unlock() }
        let expired = transfers.compactMap { key, value in
            now.timeIntervalSince(value.updatedAt) >= reassemblyTimeout ? (key, value.requestID) : nil
        }
        for item in expired { transfers.removeValue(forKey: item.0) }
        return expired
    }
}

func chunkLogicalData(_ data: Data, requestID: String? = nil, rawChunkSize: Int = hostRawChunkSize) throws -> [[String: Any]] {
    guard !data.isEmpty, data.count < 16 * 1024 * 1024, rawChunkSize > 0 else {
        throw NativeHostError.invalidFrameLength(data.count)
    }
    let transferID = UUID().uuidString.lowercased()
    let total = max(1, Int(ceil(Double(data.count) / Double(rawChunkSize))))
    let checksum = fnv1a(data)
    return try (0..<total).map { index in
        let lower = index * rawChunkSize
        let upper = min(data.count, lower + rawChunkSize)
        let part = data.subdata(in: lower..<upper)
        var chunk: [String: Any] = [
            "protocolVersion": bridgeProtocolVersion,
            "type": "chunk",
            "transferId": transferID,
            "index": index,
            "total": total,
            "byteLength": data.count,
            "checksum": checksum,
            "encoding": "base64",
            "payload": part.base64EncodedString()
        ]
        if let requestID { chunk["requestId"] = requestID }
        let encodedSize = try JSONSerialization.data(withJSONObject: chunk).count
        guard encodedSize < hostToBrowserFrameLimit else {
            throw NativeHostError.invalidFrameLength(encodedSize)
        }
        return chunk
    }
}

private final class OutgoingTransfer {
    let chunks: [[String: Any]]
    var unacknowledged: Set<Int>
    var attempts = 0
    var deadline = Date().addingTimeInterval(2)

    init(chunks: [[String: Any]]) {
        self.chunks = chunks
        self.unacknowledged = Set(chunks.indices)
    }
}

final class OutgoingTransferManager {
    private let output: FramedOutput
    private let lock = NSLock()
    private var transfers: [String: OutgoingTransfer] = [:]
    private let timer: DispatchSourceTimer
    var onFailure: ((String, String?) -> Void)?

    init(output: FramedOutput) {
        self.output = output
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.retryExpired() }
        timer.resume()
    }

    deinit { timer.cancel() }

    func sendLogicalData(_ data: Data) throws {
        let object = try jsonObject(from: data)
        let requestID = object["requestId"] as? String
        let chunks = try chunkLogicalData(data, requestID: requestID)
        guard let transferID = chunks.first?["transferId"] as? String else { return }
        let pending = OutgoingTransfer(chunks: chunks)
        lock.lock()
        transfers[transferID] = pending
        lock.unlock()
        for chunk in chunks { try output.send(chunk) }
    }

    func acknowledge(transferID: String, index: Int) {
        lock.lock()
        transfers[transferID]?.unacknowledged.remove(index)
        lock.unlock()
    }

    func complete(transferID: String) {
        lock.lock()
        transfers.removeValue(forKey: transferID)
        lock.unlock()
    }

    func fail(transferID: String) {
        lock.lock()
        let requestID = transfers[transferID]?.chunks.first?["requestId"] as? String
        transfers.removeValue(forKey: transferID)
        lock.unlock()
        onFailure?("Browser rejected transfer \(transferID)", requestID)
    }

    private func retryExpired() {
        var resend: [[String: Any]] = []
        var failed: [(String, String?)] = []
        let now = Date()
        lock.lock()
        for (transferID, transfer) in transfers where transfer.deadline <= now {
            if transfer.attempts >= 2 {
                let requestID = transfer.chunks.first?["requestId"] as? String
                failed.append((transferID, requestID))
                transfers.removeValue(forKey: transferID)
            } else {
                transfer.attempts += 1
                transfer.deadline = now.addingTimeInterval(2)
                resend.append(contentsOf: transfer.unacknowledged.sorted().map { transfer.chunks[$0] })
            }
        }
        lock.unlock()
        for chunk in resend { try? output.send(chunk) }
        for item in failed { onFailure?("Browser acknowledgement timed out for \(item.0)", item.1) }
    }
}
