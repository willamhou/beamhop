import Foundation

// Minimal MCP server over stdio (JSON-RPC 2.0). Implements:
//  - initialize
//  - notifications/initialized (no response)
//  - tools/list  -> returns beamhop_fetch_capture
//  - tools/call  -> returns fixed payload regardless of args
//
// Throw-away spike code. NOTE (deviation from plan draft): MCP's stdio transport
// uses NEWLINE-DELIMITED JSON, not LSP-style Content-Length framing. The plan's
// original draft used Content-Length, which Claude Code's MCP client does not
// speak — so this version reads/writes one JSON object per line. See notes.md.

let stdin = FileHandle.standardInput
let stdout = FileHandle.standardOutput
let stderr = FileHandle.standardError

func log(_ s: String) {
    stderr.write(Data("[hello-server] \(s)\n".utf8))
}

func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    stdout.write(data)
    stdout.write(Data("\n".utf8))
}

func handle(_ msg: [String: Any]) {
    guard let method = msg["method"] as? String else { return }
    let id = msg["id"]   // may be nil for notifications
    log("got method=\(method) id=\(String(describing: id))")

    switch method {
    case "initialize":
        // Echo back the client's protocol version when present; fall back to a known one.
        let params = msg["params"] as? [String: Any]
        let protocolVersion = (params?["protocolVersion"] as? String) ?? "2024-11-05"
        send([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "beamhop-hello", "version": "0.0.1"]
            ]
        ])
    case "notifications/initialized":
        // Notification — no response.
        break
    case "tools/list":
        send([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "tools": [
                    [
                        "name": "beamhop_fetch_capture",
                        "description": "Fetch a Beamhop capture by id (spike: returns fixed payload)",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"]
                            ]
                        ]
                    ]
                ]
            ]
        ])
    case "tools/call":
        send([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "result": [
                "content": [
                    [
                        "type": "text",
                        "text": "SPIKE_S1_OK: this is the fixed capture payload from hello-server."
                    ]
                ]
            ]
        ])
    default:
        // Only respond with an error to requests (which have an id), not notifications.
        if let id = id {
            send([
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": -32601, "message": "method not found"]
            ])
        }
    }
}

// Read newline-delimited JSON-RPC messages from stdin.
//
// NOTE (deviation from plan draft): we use raw POSIX read() on fd 0 rather than
// FileHandle.read(upToCount:). On macOS the latter blocks until the requested
// count is reached OR EOF arrives, so a single message on a still-open stdin is
// never delivered — which made Claude Code's MCP client time out at 30s. POSIX
// read() returns as soon as ANY bytes are available, which is what a streaming
// stdio transport needs. See notes.md.
var buffer = Data()
let newline = UInt8(ascii: "\n")
let chunkSize = 4096
var rawBuf = [UInt8](repeating: 0, count: chunkSize)
while true {
    let n = read(0, &rawBuf, chunkSize)
    if n <= 0 { break }  // EOF or error
    buffer.append(contentsOf: rawBuf[0..<n])
    while let nlIndex = buffer.firstIndex(of: newline) {
        let lineData = buffer.subdata(in: buffer.startIndex..<nlIndex)
        buffer.removeSubrange(buffer.startIndex...nlIndex)
        if lineData.isEmpty { continue }
        if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
            handle(json)
        } else {
            log("bad json line of \(lineData.count) bytes")
        }
    }
}
