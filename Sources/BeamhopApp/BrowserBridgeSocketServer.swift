import Darwin
import Foundation

enum BrowserBridgeSocketError: LocalizedError {
    case notConnected
    case pathTooLong
    case systemCall(String, Int32)
    case invalidFrame

    var errorDescription: String? {
        switch self {
        case .notConnected:
            "浏览器 native host 尚未连接 bridge.sock。"
        case .pathTooLong:
            "bridge.sock 路径超过 AF_UNIX 限制。"
        case .systemCall(let operation, let code):
            "\(operation) 失败（errno \(code)）。"
        case .invalidFrame:
            "浏览器 bridge 发来了无效帧。"
        }
    }
}

/// Desktop-side AF_UNIX server. Socket messages are control-plane only; capture
/// results are acknowledged exclusively through BrowserInboxConsumer.
final class BrowserBridgeSocketServer: @unchecked Sendable {
    private let stateLock = NSLock()
    private let queue = DispatchQueue(label: "com.beamhop.browser-bridge", qos: .userInitiated)
    private let socketURL: URL
    private var serverFileDescriptor: Int32 = -1
    private var clientFileDescriptor: Int32 = -1
    private var running = false
    private var onRoute: (@Sendable (String) -> Void)?

    init(socketURL: URL? = nil) {
        if let socketURL {
            self.socketURL = socketURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
            self.socketURL = support
                .appendingPathComponent("beamhop", isDirectory: true)
                .appendingPathComponent("bridge.sock", isDirectory: false)
        }
    }

    deinit {
        stop()
    }

    func start(onRoute: @escaping @Sendable (String) -> Void) {
        stateLock.lock()
        guard !running else {
            stateLock.unlock()
            return
        }
        running = true
        self.onRoute = onRoute
        stateLock.unlock()

        queue.async { [weak self] in
            self?.runAcceptLoop()
        }
    }

    func stop() {
        stateLock.lock()
        running = false
        let server = serverFileDescriptor
        let client = clientFileDescriptor
        serverFileDescriptor = -1
        clientFileDescriptor = -1
        stateLock.unlock()
        if client >= 0 { Darwin.close(client) }
        if server >= 0 { Darwin.close(server) }
        unlink(socketURL.path)
    }

    func requestCurrentTab() throws -> String {
        let requestID = UUID().uuidString.lowercased()
        let envelope: [String: Any] = [
            "protocolVersion": 1,
            "requestId": requestID,
            "route": "browser.captureCurrentTab",
            "payload": [:],
            "sentAt": ISO8601DateFormatter().string(from: Date())
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        try writeFrame(data)
        return requestID
    }

    private func runAcceptLoop() {
        do {
            try configureServer()
        } catch {
            stateLock.lock()
            running = false
            stateLock.unlock()
            return
        }

        while isRunning {
            let accepted = Darwin.accept(serverDescriptor, nil, nil)
            if accepted < 0 {
                if !isRunning { return }
                continue
            }
            var noPipe: Int32 = 1
            setsockopt(accepted, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe)))
            replaceClient(with: accepted)
            readFrames(from: accepted)
            clearClient(ifMatching: accepted)
            Darwin.close(accepted)
        }
    }

    private func configureServer() throws {
        let directory = socketURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        chmod(directory.path, S_IRWXU)
        unlink(socketURL.path)

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BrowserBridgeSocketError.systemCall("socket", errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketURL.path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else {
            Darwin.close(descriptor)
            throw BrowserBridgeSocketError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in
                destination.copyBytes(from: source)
            }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindStatus == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw BrowserBridgeSocketError.systemCall("bind", code)
        }
        chmod(socketURL.path, S_IRUSR | S_IWUSR)
        guard Darwin.listen(descriptor, 2) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw BrowserBridgeSocketError.systemCall("listen", code)
        }
        stateLock.lock()
        serverFileDescriptor = descriptor
        stateLock.unlock()
    }

    private func readFrames(from descriptor: Int32) {
        while isRunning {
            guard let header = readExactly(4, from: descriptor) else { return }
            let length = header.withUnsafeBytes { raw -> UInt32 in
                raw.loadUnaligned(as: UInt32.self).littleEndian
            }
            guard length > 0, length <= UInt32(BrowserInboxConsumer.maximumFileBytes),
                  let payload = readExactly(Int(length), from: descriptor),
                  let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let route = object["route"] as? String else {
                return
            }
            onRoute?(route)
        }
    }

    private func readExactly(_ count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        var offset = 0
        let result = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            while offset < count {
                let received = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if received <= 0 { return false }
                offset += received
            }
            return true
        }
        return result ? data : nil
    }

    private func writeFrame(_ payload: Data) throws {
        stateLock.lock()
        let descriptor = clientFileDescriptor
        stateLock.unlock()
        guard descriptor >= 0 else { throw BrowserBridgeSocketError.notConnected }
        var length = UInt32(payload.count).littleEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        try writeAll(header, to: descriptor)
        try writeAll(payload, to: descriptor)
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        var offset = 0
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < data.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                guard written > 0 else {
                    throw BrowserBridgeSocketError.systemCall("write", errno)
                }
                offset += written
            }
        }
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return running
    }

    private var serverDescriptor: Int32 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return serverFileDescriptor
    }

    private func replaceClient(with descriptor: Int32) {
        stateLock.lock()
        let previous = clientFileDescriptor
        clientFileDescriptor = descriptor
        stateLock.unlock()
        if previous >= 0 && previous != descriptor { Darwin.close(previous) }
    }

    private func clearClient(ifMatching descriptor: Int32) {
        stateLock.lock()
        if clientFileDescriptor == descriptor { clientFileDescriptor = -1 }
        stateLock.unlock()
    }
}
