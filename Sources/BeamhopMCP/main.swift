import Foundation
import BeamhopCore

// Beamhop MCP server (stdio JSON-RPC 2.0). Ported from the Week 0 S1 prototype, whose two hard
// lessons are kept: (1) MCP stdio is NEWLINE-DELIMITED JSON (not Content-Length), (2) read with
// raw POSIX read() — FileHandle.read(upToCount:) blocks and causes a 30s connection timeout.
//
// Exposes:
//   tool      fetch_capture(id?)          -> latest (or by id) Capture as JSON
//   resource  capture://latest, capture://{id}
// Reads inbox.sqlite READ-ONLY. DB path comes from `--db <path>` (the server never guesses it).

let stdoutHandle = FileHandle.standardOutput
let stderrHandle = FileHandle.standardError
func log(_ s: String) { stderrHandle.write(Data("[beamhop-mcp] \(s)\n".utf8)) }

// --- args ---
func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: flag), i + 1 < a.count { return a[i + 1] }
    return nil
}
let dbPath = argValue("--db").map { URL(fileURLWithPath: $0) }

// Open read-only lazily; keep server responsive even if DB is missing (return structured errors).
var reader: CaptureReader? = {
    guard let dbPath else { log("no --db provided"); return nil }
    do { return try CaptureReader.open(path: dbPath) }
    catch { log("open read-only failed: \(error)"); return nil }
}()

func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    stdoutHandle.write(data); stdoutHandle.write(Data("\n".utf8))
}

func rpcError(id: Any?, code: Int, message: String) {
    send(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
}

func captureText(id: String?) -> (text: String, isError: Bool) {
    guard let reader else { return ("Beamhop database unavailable (missing --db or file not found)", true) }
    do {
        let cap: Capture?
        if let id, !id.isEmpty { cap = try reader.fetch(id: id) } else { cap = try reader.latest() }
        guard let cap else { return (id == nil ? "No captures yet." : "Capture \(id!) not found.", true) }
        return (CaptureReader.renderJSON(cap), false)
    } catch { return ("read failed: \(error)", true) }
}

func handle(_ msg: [String: Any]) {
    guard let method = msg["method"] as? String else { return }
    let id = msg["id"]

    switch method {
    case "initialize":
        let params = msg["params"] as? [String: Any]
        let proto = (params?["protocolVersion"] as? String) ?? "2024-11-05"
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": [
            "protocolVersion": proto,
            "capabilities": ["tools": [String: Any](), "resources": [String: Any]()],
            "serverInfo": ["name": "beamhop", "version": "0.1.0"]
        ]])

    case "notifications/initialized":
        break

    case "tools/list":
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": ["tools": [[
            "name": "fetch_capture",
            "description": "Fetch a Beamhop capture (the latest if no id) as JSON, including provenance.",
            "inputSchema": [
                "type": "object",
                "properties": ["id": ["type": "string", "description": "capture id like cap_…; omit for latest"]]
            ]
        ]]]])

    case "tools/call":
        let params = msg["params"] as? [String: Any]
        let name = params?["name"] as? String ?? ""
        let args = params?["arguments"] as? [String: Any]
        guard name == "fetch_capture" else { rpcError(id: id, code: -32602, message: "unknown tool \(name)"); return }
        let r = captureText(id: args?["id"] as? String)
        var result: [String: Any] = ["content": [["type": "text", "text": r.text]]]
        if r.isError { result["isError"] = true }
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])

    case "resources/list":
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": ["resources": [
            ["uri": "capture://latest", "name": "Latest capture", "mimeType": "application/json"]
        ]]])

    case "resources/read":
        let params = msg["params"] as? [String: Any]
        let uri = params?["uri"] as? String ?? ""
        let capID: String? = uri == "capture://latest" ? nil
            : (uri.hasPrefix("capture://") ? String(uri.dropFirst("capture://".count)) : nil)
        let r = captureText(id: capID)
        if r.isError { rpcError(id: id, code: -32002, message: r.text) }
        else {
            send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": ["contents": [
                ["uri": uri, "mimeType": "application/json", "text": r.text]]]])
        }

    default:
        if let id = id { rpcError(id: id, code: -32601, message: "method not found: \(method)") }
    }
}

// --- newline-delimited reader over raw POSIX read (S1 lesson) ---
var buffer = Data()
let newline = UInt8(ascii: "\n")
let chunkSize = 65536
var raw = [UInt8](repeating: 0, count: chunkSize)
log("started (db=\(dbPath?.path ?? "none"))")
while true {
    let n = read(0, &raw, chunkSize)
    if n <= 0 { break }
    buffer.append(contentsOf: raw[0..<n])
    while let nl = buffer.firstIndex(of: newline) {
        let line = buffer.subdata(in: buffer.startIndex..<nl)
        buffer.removeSubrange(buffer.startIndex...nl)
        if line.isEmpty { continue }
        if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
            handle(json)
        } else {
            log("bad json line (\(line.count) bytes)")
        }
    }
}
