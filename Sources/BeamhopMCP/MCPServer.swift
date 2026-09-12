import BeamhopCore
import Foundation

final class MCPServer {
    private let repository: CaptureRepository
    private let encoder: JSONEncoder

    init(repository: CaptureRepository) {
        self.repository = repository
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func handle(_ data: Data) -> Data? {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return encode(response(id: NSNull(), errorCode: -32700, message: "Parse error"))
        }
        guard let request = object as? [String: Any] else {
            return encode(response(id: NSNull(), errorCode: -32600, message: "Invalid Request"))
        }
        return handle(request)
    }

    private func handle(_ request: [String: Any]) -> Data? {
        let id = request["id"] ?? NSNull()
        let isNotification = request["id"] == nil
        guard request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return isNotification ? nil : encode(response(id: id, errorCode: -32600, message: "Invalid Request"))
        }
        let params = request["params"] as? [String: Any] ?? [:]

        do {
            let result: [String: Any]
            switch method {
            case "initialize":
                result = initialize(params: params)
            case "ping":
                result = [:]
            case "tools/list":
                result = toolsList()
            case "tools/call":
                result = try toolsCall(params: params)
            case "resources/list":
                result = try resourcesList()
            case "resources/read":
                result = try resourcesRead(params: params)
            case "notifications/initialized", "notifications/cancelled":
                return nil
            default:
                return isNotification
                    ? nil
                    : encode(response(id: id, errorCode: -32601, message: "Method not found: \(method)"))
            }
            return isNotification ? nil : encode(response(id: id, result: result))
        } catch let error as MCPRequestError {
            return isNotification ? nil : encode(response(id: id, errorCode: error.code, message: error.message))
        } catch {
            return isNotification
                ? nil
                : encode(response(id: id, errorCode: -32603, message: "Internal error: \(error)"))
        }
    }

    private func initialize(params: [String: Any]) -> [String: Any] {
        let requested = params["protocolVersion"] as? String
        let supported = ["2025-06-18", "2025-03-26", "2024-11-05"]
        let version = requested.flatMap { supported.contains($0) ? $0 : nil } ?? supported[0]
        return [
            "protocolVersion": version,
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["subscribe": false, "listChanged": false]
            ],
            "serverInfo": ["name": "beamhop", "version": "0.1.0"],
            "instructions": "Use fetch_capture to load locally stored user captures by id. All operations are read-only."
        ]
    }

    private func toolsList() -> [String: Any] {
        [
            "tools": [[
                "name": "fetch_capture",
                "title": "Fetch Beamhop Capture",
                "description": "Fetch a local Beamhop capture by id. Omit id to fetch the latest capture.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": [
                            "type": "string",
                            "description": "Capture id such as cap_abc123. Omit for the latest capture."
                        ]
                    ],
                    "additionalProperties": false
                ],
                "annotations": [
                    "readOnlyHint": true,
                    "destructiveHint": false,
                    "idempotentHint": true,
                    "openWorldHint": false
                ]
            ]]
        ]
    }

    private func toolsCall(params: [String: Any]) throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw MCPRequestError(code: -32602, message: "tools/call requires a name")
        }
        // The longer alias keeps compatibility with the Week 0 spike while the
        // distributed tool's canonical name stays concise.
        guard name == "fetch_capture" || name == "beamhop_fetch_capture" else {
            throw MCPRequestError(code: -32602, message: "Unknown tool: \(name)")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        if let suppliedID = arguments["id"], !(suppliedID is String), !(suppliedID is NSNull) {
            throw MCPRequestError(code: -32602, message: "fetch_capture id must be a string")
        }
        let requestedID = arguments["id"] as? String
        let capture = try requestedID.map { try repository.capture(id: $0) } ?? repository.latest()
        guard let capture else {
            let description = requestedID.map { "Capture not found: \($0)" } ?? "No captures are available"
            return [
                "isError": true,
                "content": [["type": "text", "text": description]]
            ]
        }
        let object = try captureObject(capture)
        return [
            "content": [["type": "text", "text": try jsonString(object)]],
            "structuredContent": ["capture": object],
            "isError": false
        ]
    }

    private func resourcesList() throws -> [String: Any] {
        var resources: [[String: Any]] = [[
            "uri": "capture://latest",
            "name": "Latest Beamhop capture",
            "description": "The most recently created, non-deleted capture.",
            "mimeType": "application/json"
        ]]
        resources.append(contentsOf: try repository.recent(limit: 100).map { capture in
            [
                "uri": "capture://\(capture.id)",
                "name": capture.windowTitle ?? "Capture \(capture.id)",
                "description": "\(capture.appName) · \(capture.createdAt.formattedISO8601)",
                "mimeType": "application/json"
            ]
        })
        return ["resources": resources]
    }

    private func resourcesRead(params: [String: Any]) throws -> [String: Any] {
        guard let uri = params["uri"] as? String else {
            throw MCPRequestError(code: -32602, message: "resources/read requires uri")
        }
        let capture: Capture?
        if uri == "capture://latest" {
            capture = try repository.latest()
        } else if uri.hasPrefix("capture://latest/") {
            capture = try repository.capture(id: String(uri.dropFirst("capture://latest/".count)))
        } else if uri.hasPrefix("capture://") {
            capture = try repository.capture(id: String(uri.dropFirst("capture://".count)))
        } else {
            throw MCPRequestError(code: -32602, message: "Unsupported resource URI: \(uri)")
        }
        guard let capture else {
            throw MCPRequestError(code: -32002, message: "Resource not found: \(uri)")
        }
        let object = try captureObject(capture)
        return [
            "contents": [[
                "uri": uri,
                "mimeType": "application/json",
                "text": try jsonString(object)
            ]]
        ]
    }

    private func captureObject(_ capture: Capture) throws -> [String: Any] {
        let data = try encoder.encode(capture)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MCPRequestError(code: -32603, message: "Unable to encode capture")
        }
        return object
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw MCPRequestError(code: -32603, message: "Unable to encode JSON text")
        }
        return string
    }

    private func response(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func response(id: Any, errorCode: Int, message: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": errorCode, "message": message]
        ]
    }

    private func encode(_ object: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private struct MCPRequestError: Error {
    let code: Int
    let message: String
}

private extension Date {
    var formattedISO8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
