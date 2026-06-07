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

while true {
    guard let lenData = readExactly(4) else { break }
    let len = lenData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    guard len > 0 && len < 64 * 1024 * 1024 else { log("bad length \(len)"); break }
    guard let body = readExactly(Int(len)) else { break }

    guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        log("bad json"); continue
    }
    let id = obj["id"] as? Int ?? 0
    let kind = obj["kind"] as? String ?? ""

    var resp: [String: Any] = ["id": id]
    switch kind {
    case "ping":
        resp["pong"] = true
        resp["host_version"] = "0.0.1"
    case "echo":
        resp["body"] = obj["body"] ?? ""
    default:
        resp["error"] = "unknown kind"
    }

    let respData = try! JSONSerialization.data(withJSONObject: resp)
    var lenLE = UInt32(respData.count).littleEndian
    stdout.write(Data(bytes: &lenLE, count: 4))
    stdout.write(respData)
}
