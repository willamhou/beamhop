import Foundation
import os

/// App side of the browser bridge (Week 2B). Listens on a unix domain socket; the native host
/// (spawned by Chrome via connectNative) connects to it and relays frames to/from the extension.
/// The APP initiates requests (e.g. capture_active_tab); responses may arrive chunked and are
/// reassembled here. Same framing as the host: 4-byte LE length + JSON body.
///
/// Bridge contract (codex review): single active connection (the persistent port); requests are
/// serialized; per-request timeout; stale socket cleanup; socket dir 0700.
final class BrowserBridgeServer {
    static let shared = BrowserBridgeServer()
    private let log = Logger(subsystem: "com.beamhop.app", category: "bridge")

    private let socketPath: String
    private var listenFD: Int32 = -1
    private var connFD: Int32 = -1
    private let connLock = NSLock()      // guards connFD only (short critical sections)
    private let requestLock = NSLock()   // serializes requests (codex: don't hold connLock during IO)
    private var seq: Int = 0
    private let maxChunks = 4096

    init(socketPath: String? = nil) {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/beamhop")
        self.socketPath = socketPath ?? (dir as NSString).appendingPathComponent("bridge.sock")
    }

    var isConnected: Bool { connLock.lock(); defer { connLock.unlock() }; return connFD >= 0 }

    // MARK: lifecycle

    func start() {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        unlink(socketPath)   // clear stale socket

        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { log.error("socket() failed"); return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = socketPath.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { log.error("socket path too long"); return }
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dst in
                for (i, c) in bytes.enumerated() { dst[i] = c }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, size) }
        }
        guard bound == 0 else { log.error("bind() failed errno \(errno)"); return }
        chmod(socketPath, 0o600)
        guard listen(listenFD, 1) == 0 else { log.error("listen() failed"); return }

        log.info("bridge listening at \(self.socketPath, privacy: .public)")
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { if errno == EINTR { continue } else { break } }
            connLock.lock()
            if connFD >= 0 { close(connFD) }   // replace previous (latest host wins)
            connFD = fd
            // 5s receive timeout so a hung extension can't block a request forever.
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            connLock.unlock()
            log.info("host connected")
        }
    }

    // MARK: request/response

    /// Send a request and await the (possibly chunked) response. Returns the parsed `result`
    /// dict, or nil on no-connection / timeout / error.
    func request(type: String, timeout: TimeInterval = 5) -> [String: Any]? {
        requestLock.lock(); defer { requestLock.unlock() }   // serialize requests (no connLock during IO)

        connLock.lock(); let fd = connFD; connLock.unlock()
        guard fd >= 0 else { return nil }
        seq += 1
        let reqID = seq

        let req: [String: Any] = ["reqID": reqID, "type": type]
        guard let body = try? JSONSerialization.data(withJSONObject: req), writeFrame(fd, body) else {
            drop(fd); return nil
        }

        // Reassemble: accept single-frame {reqID, ok, result/error} or multi-frame chunks.
        var chunks: [Int: String] = [:]
        var total = -1
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard let frame = readFrame(fd) else { drop(fd); return nil }
            guard let msg = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                  (msg["reqID"] as? Int) == reqID else { continue }
            if let chunk = msg["chunk"] as? [String: Any],
               let seqN = chunk["seq"] as? Int, let t = chunk["total"] as? Int,
               let data = chunk["data"] as? String {
                guard t > 0, t <= maxChunks, seqN >= 0, seqN < t else {
                    log.error("bad chunk seq=\(seqN) total=\(t)"); return nil
                }
                total = t
                chunks[seqN] = data
                if chunks.count == total {
                    // require every seq present before joining (codex: no silent drop)
                    guard (0..<total).allSatisfy({ chunks[$0] != nil }) else {
                        log.error("missing chunk(s) in reassembly"); return nil
                    }
                    return parseResult((0..<total).map { chunks[$0]! }.joined())
                }
            } else {
                return resultFrom(msg)
            }
        }
        log.error("bridge request '\(type, privacy: .public)' timed out")
        return nil
    }

    private func resultFrom(_ msg: [String: Any]) -> [String: Any]? {
        if (msg["ok"] as? Bool) == true { return (msg["result"] as? [String: Any]) ?? [:] }
        return nil
    }
    private func parseResult(_ json: String) -> [String: Any]? {
        guard let d = json.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return resultFrom(m)
    }

    /// Close the connection only if it's still the fd we were using (avoid closing a newer one).
    private func drop(_ fd: Int32) {
        connLock.lock()
        if connFD == fd { close(connFD); connFD = -1 }
        connLock.unlock()
    }

    // MARK: framing (4-byte LE + body)

    private func writeFrame(_ fd: Int32, _ body: Data) -> Bool {
        var le = UInt32(body.count).littleEndian
        var data = Data(bytes: &le, count: 4); data.append(body)
        var off = 0
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while off < data.count {
                let n = write(fd, base + off, data.count - off)
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }
    private func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(); data.reserveCapacity(count)
        var buf = [UInt8](repeating: 0, count: 65536)
        while data.count < count {
            let want = min(buf.count, count - data.count)
            let n = read(fd, &buf, want)
            if n <= 0 { return nil }
            data.append(contentsOf: buf[0..<n])
        }
        return data
    }
    private func readFrame(_ fd: Int32) -> Data? {
        guard let lenData = readExactly(fd, 4) else { return nil }
        let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard len > 0 && len < 64 * 1024 * 1024 else { return nil }
        return readExactly(fd, Int(len))
    }
}
