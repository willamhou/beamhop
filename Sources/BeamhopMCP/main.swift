import Foundation
import BeamhopCore

// Beamhop MCP server (stdio JSON-RPC 2.0). Ported from the Week 0 S1 prototype, whose two hard
// lessons are kept: (1) MCP stdio is NEWLINE-DELIMITED JSON (not Content-Length), (2) read with
// raw POSIX read() — FileHandle.read(upToCount:) blocks and causes a 30s connection timeout.
//
// Exposes (memory-mcp-decision spec 2026-10-18):
//   tool  fetch_capture(id?)          -> latest (or by id) Capture as JSON (read-only)
//   tool  search_captures(query)      -> FTS5 dual-table recall, ranked (read-only)
//   tool  fetch_results(origin_id?)   -> agent write-backs for a capture (or latest across all)
//   tool  save_result(origin, content, agent, session_id?)
//                                     -> agent writes a conclusion back into the Inbox
//   tool  fetch_handoff(handoff_id)   -> opted-in edited handoff snapshot only
//   tool  save_handoff_result(handoff_id, content, agent, session_id?)
//   tool  fetch_handoff_results(handoff_id, limit?)
// Ordinary Hop conclusions use the frozen attempt ID, never a guessed latest capture.
// Resource capture://latest, capture://{id} unchanged.
// Captures are read through a READ-ONLY connection; results go through a lazily opened
// read-write ResultStore that never migrates (the app owns the DB). Reads inbox.sqlite.
// DB path comes from `--db <path>` (the server never guesses it).

let stdoutHandle = FileHandle.standardOutput
let stderrHandle = FileHandle.standardError
func log(_ s: String) { stderrHandle.write(Data("[beamhop-mcp] \(s)\n".utf8)) }

// --- args ---
func argValue(_ flag: String) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: flag), i + 1 < a.count { return a[i + 1] }
    return nil
}
// DB path comes from `--db <path>`; when absent (e.g. the MCPB bundle launches us with no args)
// we fall back to the standard Beamhop Inbox location so bundled installs work out of the box.
var dbPath = argValue("--db").map { URL(fileURLWithPath: $0) }
if dbPath == nil {
    dbPath = AppPaths.databaseURL
    log("no --db; defaulting to \(dbPath?.path ?? "?")")
}

// Open read-only lazily; keep server responsive even if DB is missing (return structured errors).
var reader: CaptureReader? = {
    guard let dbPath else { log("no --db provided"); return nil }
    do { return try CaptureReader.open(path: dbPath) }
    catch { log("open read-only failed: \(error)"); return nil }
}()

/// Lazily opened read-write access for result tools. Never migrates: if the app hasn't
/// restarted since migration v3, open throws schemaOutdated → structured MCP error.
var resultStore: ResultStore?
func resultsStore() -> ResultStore? {
    if let resultStore { return resultStore }
    guard let dbPath else { return nil }
    do {
        resultStore = try ResultStore.open(path: dbPath)
    } catch {
        log("result store open failed: \(error)")
        return nil
    }
    return resultStore
}

var handoffResultStore: HandoffResultStore?
func handoffStore() -> HandoffResultStore? {
    if let handoffResultStore { return handoffResultStore }
    guard let dbPath else { return nil }
    do {
        let store = try HandoffResultStore.open(path: dbPath)
        handoffResultStore = store
        return store
    } catch { return nil }
}

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
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": ["tools": [
            [
                "name": "fetch_capture",
                "description": "Fetch a Beamhop capture (the latest if no id) as JSON, including provenance.",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "string", "description": "capture id like cap_…; omit for latest"]]
                ]
            ],
            [
                "name": "search_captures",
                "description": "Full-text search the Beamhop Inbox (English word-level + CJK substring), ranked by relevance and recency. Re-captures of the same page/content are collapsed by default: each hit is the newest capture of its group, annotated with duplicate_count / first_seen_at / last_seen_at. Use to recall captures related to a topic before answering.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "search text (>=3 chars for CJK)"],
                        "limit": ["type": "integer", "description": "max results, default 10"],
                        "include_duplicates": ["type": "boolean", "description": "return the raw hit list without collapsing re-captures (default false)"]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "fetch_results",
                "description": "Fetch agent write-back conclusions: for one capture if origin_capture_id is given, otherwise the most recent across all captures. Pairs a capture (the question) with its agent conclusions (the answers).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "origin_capture_id": ["type": "string", "description": "capture id like cap_…; omit for latest across all"],
                        "limit": ["type": "integer", "description": "max results, default 20"]
                    ]
                ]
            ],
            [
                "name": "save_result",
                "description": "Write your conclusion about a Beamhop capture back into the Inbox so it is remembered and shared across the user's agents. Call this after you finish processing a fetched capture.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "origin_capture_id": ["type": "string", "description": "the capture id you processed (cap_…)"],
                        "content": ["type": "string", "description": "your conclusion text, verbatim — do not distill away detail"],
                        "agent": ["type": "string", "description": "your identifier, e.g. claude_code / codex / kimi"],
                        "session_id": ["type": "string", "description": "your session id (optional)"]
                    ],
                    "required": ["origin_capture_id", "content", "agent"]
                ]
            ],
            [
                "name": "fetch_handoff",
                "description": "Read the exact edited Hop handoff by ID, only when the user enabled optional conclusion return. Does not expose original captures or local file paths. Never substitute fetch_capture for these edited materials.",
                "inputSchema": ["type": "object", "properties": ["handoff_id": ["type": "string"]], "required": ["handoff_id"]]
            ],
            [
                "name": "save_handoff_result",
                "description": "Optionally return your conclusion for the exact Hop handoff the user shared. Requires return opt-in. This only appends an agent-reported conclusion; it does not verify completion or alter copied/prepared status. If unavailable, answer normally without claiming a saved result.",
                "inputSchema": ["type": "object", "properties": [
                    "handoff_id": ["type": "string"], "content": ["type": "string"],
                    "agent": ["type": "string"], "session_id": ["type": "string"]
                ], "required": ["handoff_id", "content", "agent"]]
            ],
            [
                "name": "fetch_handoff_results",
                "description": "Read returned conclusions for an exact opted-in Hop handoff. Requires its ID; no latest-handoff guessing.",
                "inputSchema": ["type": "object", "properties": [
                    "handoff_id": ["type": "string"], "limit": ["type": "integer", "minimum": 1, "maximum": 100]
                ], "required": ["handoff_id"]]
            ],
        ]]])

    case "tools/call":
        let params = msg["params"] as? [String: Any]
        let name = params?["name"] as? String ?? ""
        let args = params?["arguments"] as? [String: Any]
        let limit: Int?
        if let value = (args?["limit"] as? NSNumber)?.doubleValue, value.isFinite {
            limit = Int(min(100, max(1, value)))
        } else { limit = nil }

        func reply(_ text: String, isError: Bool = false) {
            var result: [String: Any] = ["content": [["type": "text", "text": text]]]
            if isError { result["isError"] = true }
            send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
        }

        switch name {
        case "fetch_handoff", "save_handoff_result", "fetch_handoff_results":
            guard let handoffID = args?["handoff_id"] as? String, !handoffID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reply("This tool requires an exact handoff_id.", isError: true); break
            }
            guard let store = handoffStore() else {
                reply("Hop results unavailable. Open the updated Beamhop app to migrate its database; MCP never creates or migrates it.", isError: true); break
            }
            do {
                let snapshot = try store.snapshot(handoffID: handoffID)
                if name == "fetch_handoff" { reply(CaptureReader.renderJSON(snapshot)) }
                else if name == "fetch_handoff_results" {
                    reply(CaptureReader.renderJSON(try store.results(handoffID: handoffID, limit: limit ?? 20)))
                } else {
                    guard let content = args?["content"] as? String, let agent = args?["agent"] as? String else {
                        reply("save_handoff_result requires content and agent strings.", isError: true); break
                    }
                    let result = HandoffResult(handoffID: handoffID, agent: agent,
                                               sessionID: args?["session_id"] as? String, content: content)
                    try store.insert(result)
                    reply(CaptureReader.renderJSON(result))
                }
            } catch let error as HandoffResultStore.ReturnError {
                reply(error.localizedDescription, isError: true)
            } catch {
                reply("Could not read or save a handoff conclusion. Check Beamhop and retry; no completion is implied.", isError: true)
            }

        case "fetch_capture":
            let r = captureText(id: args?["id"] as? String)
            reply(r.text, isError: r.isError)

        case "search_captures":
            guard let reader else { reply("Beamhop database unavailable (missing --db or file not found)", isError: true); break }
            guard let query = args?["query"] as? String else { reply("search_captures requires a 'query' argument", isError: true); break }
            let includeDupes = (args?["include_duplicates"] as? Bool) ?? false
            do {
                if includeDupes {
                    let caps = try reader.search(query, limit: min(limit ?? 10, 50))
                    reply(CaptureReader.renderJSON(caps))
                } else {
                    let hits = try reader.searchDeduplicated(query, limit: min(limit ?? 10, 50))
                    reply(CaptureReader.renderJSON(hits))
                }
            } catch { reply("search failed: \(error)", isError: true) }

        case "fetch_results":
            guard let store = resultsStore() else {
                reply("Beamhop results unavailable (DB missing, or app not restarted since schema update)", isError: true); break
            }
            do {
                let res: [CaptureResult]
                if let origin = args?["origin_capture_id"] as? String, !origin.isEmpty {
                    res = try store.results(captureID: origin, limit: min(limit ?? 20, 100))
                } else {
                    res = try store.recentResults(limit: min(limit ?? 20, 100))
                }
                reply(CaptureReader.renderJSON(res))
            } catch { reply("fetch_results failed: \(error)", isError: true) }

        case "save_result":
            guard let store = resultsStore() else {
                reply("Beamhop results unavailable (DB missing, or app not restarted since schema update)", isError: true); break
            }
            guard let origin = args?["origin_capture_id"] as? String, !origin.isEmpty else {
                reply("save_result requires 'origin_capture_id'", isError: true); break
            }
            guard let content = args?["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reply("save_result requires non-empty 'content'", isError: true); break
            }
            guard let agent = args?["agent"] as? String, !agent.isEmpty else {
                reply("save_result requires 'agent' (your identifier, e.g. claude_code / codex)", isError: true); break
            }
            let result = CaptureResult(originCaptureID: origin, agent: agent,
                                       sessionID: args?["session_id"] as? String,
                                       content: content)
            do {
                try store.insert(result)
                reply(CaptureReader.renderJSON(result))
            } catch {
                // Most common case: FK rejection because the origin capture doesn't exist.
                reply("save_result failed: \(error)", isError: true)
            }

        default:
            rpcError(id: id, code: -32602, message: "unknown tool \(name)")
        }

    case "resources/list":
        send(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": ["resources": [
            ["uri": "capture://latest", "name": "Latest capture", "mimeType": "application/json"]
        ]]])

    case "resources/read":
        let params = msg["params"] as? [String: Any]
        let uri = params?["uri"] as? String ?? ""
        // codex: validate the scheme — don't let a stray uri fall through to "latest".
        guard uri == "capture://latest" || uri.hasPrefix("capture://") else {
            rpcError(id: id, code: -32602, message: "invalid resource uri: \(uri)"); return
        }
        let capID: String? = uri == "capture://latest" ? nil : String(uri.dropFirst("capture://".count))
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
