import Foundation

// Beamhop native messaging host = a PURE FRAME RELAY between Chrome (stdio, native-messaging
// framing) and the Beamhop app (unix domain socket). Both sides use the SAME framing:
// 4-byte little-endian length prefix + body. The host never parses payloads — it just shuttles
// whole frames, so chunking/reassembly lives in the app + extension (bidirectional).
//
// Lifecycle (Week 2 bridge contract): on launch, connect to the app socket. If the app isn't
// running / socket missing, exit — the extension's connectNative will respawn us next time.
// Ported framing from Week 0 spike S4 (exact-length POSIX reads, loadUnaligned).

let SOCK_PATH = (ProcessInfo.processInfo.environment["BEAMHOP_BRIDGE_SOCK"]
    ?? (NSHomeDirectory() + "/Library/Application Support/beamhop/bridge.sock"))

let stderrH = FileHandle.standardError
func log(_ s: String) { stderrH.write(Data("[bridge] \(s)\n".utf8)) }

// ---- low-level exact-length IO on a raw fd ----
func readExactly(_ fd: Int32, _ count: Int) -> Data? {
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
func writeAll(_ fd: Int32, _ data: Data) -> Bool {
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
func readFrame(_ fd: Int32) -> Data? {
    guard let lenData = readExactly(fd, 4) else { return nil }
    let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard len > 0 && len < 64 * 1024 * 1024 else { log("bad frame len \(len)"); return nil }
    return readExactly(fd, Int(len))
}
func writeFrame(_ fd: Int32, _ body: Data) -> Bool {
    var le = UInt32(body.count).littleEndian
    var header = Data(bytes: &le, count: 4)
    header.append(body)
    return writeAll(fd, header)
}

// ---- connect to the app unix socket ----
func connectAppSocket(_ path: String) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 { return nil }
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(fd); return nil }
    withUnsafeMutablePointer(to: &addr.sun_path) {
        $0.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dst in
            for (i, c) in pathBytes.enumerated() { dst[i] = c }
        }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let r = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, size) }
    }
    if r != 0 { close(fd); return nil }
    return fd
}

let chromeIn: Int32 = 0   // stdin from Chrome
let chromeOut: Int32 = 1  // stdout to Chrome

guard let sock = connectAppSocket(SOCK_PATH) else {
    log("app socket not available at \(SOCK_PATH) (errno \(errno)) — exiting so extension respawns later")
    exit(0)
}
log("connected to app socket")

// relay Chrome → app. On end, half-close the socket (codex: don't exit(0) from a worker thread
// while the main thread may be writing a response) so the main loop's readFrame returns and we
// exit cleanly from main.
let t1 = Thread {
    while let frame = readFrame(chromeIn) {
        if !writeFrame(sock, frame) { break }
    }
    shutdown(sock, SHUT_RDWR)   // unblocks the main thread's readFrame(sock)
}
t1.start()

// relay app → Chrome (main thread)
while let frame = readFrame(sock) {
    if !writeFrame(chromeOut, frame) { break }
}
close(sock)
