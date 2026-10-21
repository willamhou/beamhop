import Foundation

/// Pure merge for explicit MCP registration. Invalid existing content must never be
/// treated as an empty document, or registration would erase unrelated user settings.
public enum MCPRegistrationConfig {
    public enum Invalid: Error { case root, servers }
    public static func updating(_ existing: Data?, name: String, command: String, arguments: [String]) throws -> Data {
        var document: [String: Any] = [:]
        if let existing {
            guard let parsed = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else { throw Invalid.root }
            document = parsed
        }
        var servers: [String: Any] = [:]
        if let value = document["mcpServers"] {
            guard let parsed = value as? [String: Any] else { throw Invalid.servers }
            servers = parsed
        }
        servers[name] = ["command": command, "args": arguments]
        document["mcpServers"] = servers
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }
}
