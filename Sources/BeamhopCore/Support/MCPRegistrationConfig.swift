import Foundation

/// Pure merge for explicit MCP registration. Invalid existing content must never be
/// treated as an empty document, or registration would erase unrelated user settings.
public enum MCPRegistrationConfig {
    public enum Invalid: Error { case root, servers }

    /// Installation alone does not reliably identify Desktop's deployment. Register both
    /// supported homes, including a missing current config when a legacy file is present.
    public static func desktopURLs(in applicationSupport: URL) -> [URL] {
        ["Claude", "Claude-3p"].map {
            applicationSupport.appendingPathComponent("\($0)/claude_desktop_config.json")
        }
    }

    public static func registerDesktop(in applicationSupport: URL, name: String,
                                       command: String, arguments: [String]) throws {
        let fm = FileManager.default
        // Validate every existing document before changing any of them.
        let updates = try desktopURLs(in: applicationSupport).map { url -> (URL, Data) in
            let previous = fm.fileExists(atPath: url.path) ? try Data(contentsOf: url) : nil
            return (url, try updating(previous, name: name, command: command, arguments: arguments))
        }
        for (url, data) in updates {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

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
