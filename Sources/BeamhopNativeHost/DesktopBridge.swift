import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func socketStreamType() -> Int32 {
#if os(Linux)
    return Int32(SOCK_STREAM.rawValue)
#else
    return SOCK_STREAM
#endif
}

private func closeSocket(_ descriptor: Int32) {
#if canImport(Darwin)
    _ = Darwin.close(descriptor)
#else
    _ = Glibc.close(descriptor)
#endif
}

private func socketRead(_ descriptor: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int) -> Int {
#if canImport(Darwin)
    return Darwin.read(descriptor, buffer, count)
#else
    return Glibc.read(descriptor, buffer, count)
#endif
}

private func socketWrite(_ descriptor: Int32, _ buffer: UnsafeRawPointer, _ count: Int) -> Int {
#if canImport(Darwin)
    return Darwin.write(descriptor, buffer, count)
#else
    return Glibc.write(descriptor, buffer, count)
#endif
}

private func shutdownSocket(_ descriptor: Int32) {
#if canImport(Darwin)
    _ = Darwin.shutdown(descriptor, SHUT_RDWR)
#else
    _ = Glibc.shutdown(descriptor, Int32(SHUT_RDWR))
#endif
}

final class DesktopBridge {
    enum Delivery: String { case queue, unavailable }

    private let socketPath: String
    private let queueDirectory: URL
    private let lock = NSLock()
    private let queueLock = NSLock()
    private var descriptor: Int32 = -1
    private var stopped = false
    private let connectionQueue = DispatchQueue(label: "com.beamhop.native-host.socket", qos: .utility)
    private let reconnectTimer: DispatchSourceTimer
    var onMessage: ((Data) -> Void)?
    var onStatus: ((String, String?) -> Void)?

    init(socketPath: String? = nil, queueDirectory: URL? = nil) {
        let environmentPath = ProcessInfo.processInfo.environment["BEAMHOP_BRIDGE_SOCKET"]
        self.socketPath = socketPath ?? environmentPath ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/beamhop/bridge.sock").path
        self.queueDirectory = queueDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/beamhop/browser-inbox", isDirectory: true)
        reconnectTimer = DispatchSource.makeTimerSource(queue: connectionQueue)
        reconnectTimer.schedule(deadline: .now(), repeating: 2)
        reconnectTimer.setEventHandler { [weak self] in self?.connectIfNeeded() }
    }

    func start() {
        _ = prepareQueueDirectory()
        reconnectTimer.resume()
    }

    func stop() {
        lock.lock()
        stopped = true
        let current = descriptor
        descriptor = -1
        lock.unlock()
        reconnectTimer.cancel()
        if current >= 0 { shutdownSocket(current) }
    }

    func deliver(_ data: Data) -> Delivery {
        guard let fileName = persist(data) else { return .unavailable }
        notifyQueueAvailable(fileName: fileName)
        connectionQueue.async { [weak self] in self?.connectIfNeeded() }
        return .queue
    }

    private func prepareQueueDirectory() -> Bool {
        do {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: queueDirectory.path, isDirectory: &isDirectory) {
                let attributes = try FileManager.default.attributesOfItem(atPath: queueDirectory.path)
                guard isDirectory.boolValue, attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                    onStatus?("unavailable", "Bridge queue path is not a real directory")
                    return false
                }
            }
            try FileManager.default.createDirectory(at: queueDirectory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: queueDirectory.path)
            return true
        } catch {
            onStatus?("unavailable", "Could not create bridge queue: \(error)")
            return false
        }
    }

    private func connectIfNeeded() {
        lock.lock()
        let shouldConnect = !stopped && descriptor < 0
        lock.unlock()
        guard shouldConnect else { return }

        let candidate = socket(AF_UNIX, socketStreamType(), 0)
        guard candidate >= 0 else {
            onStatus?("queue", "Could not create Unix socket")
            return
        }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8) + [0]
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= capacity else {
            closeSocket(candidate)
            onStatus?("queue", "Unix socket path is too long")
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.copyBytes(from: pathBytes)
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(candidate, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            closeSocket(candidate)
            onStatus?("queue", nil)
            return
        }

        lock.lock()
        if stopped || descriptor >= 0 {
            lock.unlock()
            closeSocket(candidate)
            return
        }
        descriptor = candidate
        lock.unlock()
        onStatus?("socket", nil)
        notifyQueueAvailable(fileName: nil)
        connectionQueue.async { [weak self] in self?.readLoop(candidate) }
    }

    private func readLoop(_ socket: Int32) {
        while let frame = readFrame(socket), frame.count < 16 * 1024 * 1024 {
            guard (try? JSONSerialization.jsonObject(with: frame)) != nil else { continue }
            onMessage?(frame)
        }
        disconnect(socket)
    }

    private func disconnect(_ socket: Int32) {
        lock.lock()
        if descriptor == socket { descriptor = -1 }
        lock.unlock()
        closeSocket(socket)
        onStatus?("queue", "Desktop app disconnected; messages will be queued")
    }

    private func readFrame(_ socket: Int32) -> Data? {
        guard let header = readExactly(socket, count: 4) else { return nil }
        let bytes = [UInt8](header)
        let length = Int(UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) |
            (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24))
        guard length > 0, length < 16 * 1024 * 1024 else { return nil }
        return readExactly(socket, count: length)
    }

    private func readExactly(_ socket: Int32, count: Int) -> Data? {
        var result = Data(count: count)
        var offset = 0
        let readSucceeded = result.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while offset < count {
                let amount = socketRead(socket, base.advanced(by: offset), count - offset)
                if amount <= 0 { return false }
                offset += amount
            }
            return true
        }
        return readSucceeded ? result : nil
    }

    private func writeFrame(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { return false }
        let length = UInt32(data.count)
        var framed = Data([
            UInt8(length & 0xff), UInt8((length >> 8) & 0xff),
            UInt8((length >> 16) & 0xff), UInt8((length >> 24) & 0xff)
        ])
        framed.append(data)
        let written = framed.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var offset = 0
            while offset < buffer.count {
                let amount = socketWrite(descriptor, base.advanced(by: offset), buffer.count - offset)
                if amount <= 0 { return false }
                offset += amount
            }
            return true
        }
        if !written {
            let failedDescriptor = descriptor
            descriptor = -1
            shutdownSocket(failedDescriptor)
        }
        return written
    }

    private func persist(_ data: Data) -> String? {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            onStatus?("unavailable", "Bridge message exceeds 8 MiB or is not valid JSON")
            return nil
        }
        queueLock.lock()
        defer { queueLock.unlock() }
        guard prepareQueueDirectory() else { return nil }
        let existing = queuedFiles()
        let existingBytes = existing.reduce(0) { sum, file in
            sum + ((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard existing.count < 100, existingBytes + data.count <= 20 * 1024 * 1024 else {
            onStatus?("unavailable", "Browser inbox is full; consume existing messages before retrying")
            return nil
        }
        let milliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        let fileName = String(format: "%013lld-%@.json", milliseconds, UUID().uuidString.lowercased())
        let target = queueDirectory.appendingPathComponent(fileName, isDirectory: false)
        do {
            try data.write(to: target, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            onStatus?("queue", nil)
            return fileName
        } catch {
            onStatus?("unavailable", "Could not persist bridge message: \(error)")
            return nil
        }
    }

    private func queuedFiles() -> [URL] {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey
        ]
        let files = (try? FileManager.default.contentsOfDirectory(at: queueDirectory,
            includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])) ?? []
        return files.filter { file in
            let values = try? file.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return false }
            let name = file.lastPathComponent
            guard name.count == 55, name.hasSuffix(".json") else { return false }
            let pieces = name.dropLast(5).split(separator: "-", maxSplits: 1)
            guard pieces.count == 2, pieces[0].count == 13,
                  Int64(String(pieces[0])) != nil else { return false }
            return UUID(uuidString: String(pieces[1])) != nil && String(pieces[1]) == String(pieces[1]).lowercased()
        }.sorted { left, right in
            let leftDate = (try? left.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let rightDate = (try? right.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }
    }

    private func notifyQueueAvailable(fileName: String?) {
        var payload: [String: Any] = ["queueDirectory": queueDirectory.path]
        if let fileName { payload["fileName"] = fileName }
        let notification: [String: Any] = [
            "protocolVersion": bridgeProtocolVersion,
            "requestId": UUID().uuidString.lowercased(),
            "route": "bridge.queueAvailable",
            "payload": payload,
            "sentAt": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: notification) {
            _ = writeFrame(data)
        }
    }
}
