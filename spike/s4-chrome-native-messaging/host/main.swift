import Foundation

// Chrome native messaging host.
// Frame: 4-byte little-endian length prefix + JSON body.
//
// NOTE (lesson from S1): we read with raw POSIX read() in an exact-length loop, NOT
// FileHandle.read(upToCount:). FileHandle.read(upToCount:) blocks until the full count
// or EOF, which deadlocks a streaming protocol when a message arrives in multiple
// chunks. readExactly() loops until it has exactly `count` bytes or hits EOF.

let stdout = FileHandle.standardOutput
let stderr = FileHandle.standardError
func log(_ s: String) { stderr.write(Data("[bridge] \(s)\n".utf8)) }

// diagnostic: prove connectNative actually spawned us (append, since Chrome spawns one host
// process per connectNative call).
if let argv = CommandLine.arguments.dropFirst().first {
    let line = "spawned \(ISO8601DateFormatter().string(from: Date())) origin=\(argv)\n"
    if let h = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/beamhop_s4_host_alive.txt")) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.data(using: .utf8)?.write(to: URL(fileURLWithPath: "/tmp/beamhop_s4_host_alive.txt"))
    }
}

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    data.reserveCapacity(count)
    var buf = [UInt8](repeating: 0, count: 65536)
    while data.count < count {
        let want = min(buf.count, count - data.count)
        let n = read(0, &buf, want)
        if n <= 0 { return nil }  // EOF or error
        data.append(contentsOf: buf[0..<n])
    }
    return data
}

func writeFrame(_ obj: [String: Any]) {
    let data: Data
    do { data = try JSONSerialization.data(withJSONObject: obj) }
    catch {
        // never crash the host; emit a framed error instead
        let fallback = "{\"error\":\"encode failed\"}".data(using: .utf8)!
        var l = UInt32(fallback.count).littleEndian
        stdout.write(Data(bytes: &l, count: 4)); stdout.write(fallback); return
    }
    var lenLE = UInt32(data.count).littleEndian
    stdout.write(Data(bytes: &lenLE, count: 4))
    stdout.write(data)
}

while true {
    guard let lenData = readExactly(4) else { break }
    // loadUnaligned avoids an alignment trap on the 4-byte slice
    let len = lenData.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard len > 0 && len < 64 * 1024 * 1024 else { log("bad length \(len)"); break }
    guard let body = readExactly(Int(len)) else { break }

    guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        log("bad json"); writeFrame(["error": "bad json"]); continue
    }
    let id = obj["id"] as? Int ?? 0
    let kind = obj["kind"] as? String ?? ""

    var resp: [String: Any] = ["id": id]
    switch kind {
    case "report":
        // automation hook: persist the extension's test results to a file we can read.
        if let payload = obj["data"] {
            if let d = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
                try? d.write(to: URL(fileURLWithPath: "/tmp/beamhop_s4_result.json"))
                log("wrote /tmp/beamhop_s4_result.json (\(d.count) bytes)")
            }
        }
        resp["saved"] = true
    case "ping":
        resp["pong"] = true
        resp["host_version"] = "0.0.2"
    case "echo":
        // echo body back. If "size" is given, generate a payload of that many bytes here so
        // the EXTENSION->host message stays tiny and we test the host->extension limit.
        if let size = obj["size"] as? Int, size > 0 {
            resp["body"] = String(repeating: "A", count: size)
            resp["generated"] = true
        } else {
            resp["body"] = obj["body"] ?? ""
        }
    default:
        resp["error"] = "unknown kind"
    }
    log("kind=\(kind) id=\(id) -> resp bytes ~\((resp["body"] as? String)?.count ?? 0)")
    writeFrame(resp)
}
