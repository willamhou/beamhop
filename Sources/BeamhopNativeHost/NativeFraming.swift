import Foundation

enum NativeHostError: Error, CustomStringConvertible {
    case endOfStream
    case invalidFrameLength(Int)
    case invalidJSON
    case invalidMessage(String)
    case socket(String)

    var description: String {
        switch self {
        case .endOfStream: return "end of stream"
        case .invalidFrameLength(let length): return "invalid frame length: \(length)"
        case .invalidJSON: return "invalid JSON"
        case .invalidMessage(let message): return message
        case .socket(let message): return message
        }
    }
}

final class FramedInput {
    private let handle: FileHandle
    private let maximumLength: Int

    init(handle: FileHandle, maximumLength: Int) {
        self.handle = handle
        self.maximumLength = maximumLength
    }

    func readFrame() throws -> Data {
        let header = try readExactly(4)
        let bytes = [UInt8](header)
        let length = Int(UInt32(bytes[0]) |
            (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) |
            (UInt32(bytes[3]) << 24))
        guard length > 0, length < maximumLength else {
            throw NativeHostError.invalidFrameLength(length)
        }
        return try readExactly(length)
    }

    private func readExactly(_ count: Int) throws -> Data {
        var result = Data()
        while result.count < count {
            let part = handle.readData(ofLength: count - result.count)
            if part.isEmpty { throw NativeHostError.endOfStream }
            result.append(part)
        }
        return result
    }
}

final class FramedOutput {
    private let handle: FileHandle
    private let maximumLength: Int
    private let lock = NSLock()

    init(handle: FileHandle, maximumLength: Int) {
        self.handle = handle
        self.maximumLength = maximumLength
    }

    func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard data.count > 0, data.count < maximumLength else {
            throw NativeHostError.invalidFrameLength(data.count)
        }
        try send(data)
    }

    func send(_ data: Data) throws {
        guard data.count > 0, data.count < maximumLength else {
            throw NativeHostError.invalidFrameLength(data.count)
        }
        let length = UInt32(data.count)
        let header = Data([
            UInt8(length & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 24) & 0xff)
        ])
        lock.lock()
        defer { lock.unlock() }
        handle.write(header)
        handle.write(data)
    }
}

func jsonObject(from data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NativeHostError.invalidJSON
    }
    return value
}

func jsonData(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [])
}
