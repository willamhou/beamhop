import Foundation
import AppKit
import BeamhopCore

enum DiagState { case ok, fail, warn, todo
    var symbol: String {
        switch self { case .ok: return "✅"; case .fail: return "❌"; case .warn: return "⚠️"; case .todo: return "🚧" }
    }
}

struct DiagRow: Identifiable {
    let id = UUID()
    let name: String
    let state: DiagState
    let detail: String
    let fixTitle: String?
    let fix: (() -> Void)?
}

/// Computes the Permission Diagnostics rows (spec §12.2). Week 1: real reads for the ones we can
/// (Accessibility, Screen Recording, Claude Code MCP, ChatGPT install); the rest are honestly
/// marked 🚧 Week 2 / Phase 1.5 rather than faked ✅ (codex review).
struct DiagnosticsService {
    let permissions = PermissionService()
    private let knownChatGPTVersion = "1.2026.119"   // from Week 0 Compatibility Matrix v0

    func rows() -> [DiagRow] {
        [accessibilityRow(), screenRecordingRow(), chromeHostRow(),
         claudeCodeMCPRow(), coworkRow(), chatGPTRow(), hotkeyRow()]
    }

    // injected so we can show hotkey-conflict state
    var hotkeyConflicts: [String] = []

    private func accessibilityRow() -> DiagRow {
        let ok = permissions.accessibility() == .granted
        return DiagRow(name: "Accessibility permission",
                       state: ok ? .ok : .fail,
                       detail: ok ? "Granted" : "Not granted — capture depends on it",
                       fixTitle: ok ? nil : "Open System Settings",
                       fix: ok ? nil : { permissions.openAccessibilitySettings() })
    }

    private func screenRecordingRow() -> DiagRow {
        let ok = permissions.preflightScreenRecording() == .granted
        return DiagRow(name: "Screen Recording permission",
                       state: ok ? .ok : .warn,
                       detail: ok ? "Granted" : "Not granted (only screenshots need it — skippable)",
                       fixTitle: ok ? nil : "Open System Settings",
                       fix: ok ? nil : { permissions.openScreenRecordingSettings() })
    }

    private func chromeHostRow() -> DiagRow {
        // Week 1 has no host binary yet → fixed 🚧 (do NOT infer ✅ from a stray manifest). codex.
        DiagRow(name: "Chrome native messaging host",
                state: .todo,
                detail: "Week 2 implementation (host binary + manifest install)",
                fixTitle: nil, fix: nil)
    }

    /// "Claude MCP registration" covers BOTH homes of the beamhop MCP server: Claude Code CLI
    /// (~/.claude.json via `claude mcp add`) and Claude Desktop (mcpServers in
    /// claude_desktop_config.json). A machine with only Claude Desktop (no `claude` CLI)
    /// registers by editing the Desktop config directly (2026-10-21).
    private func claudeCodeMCPRow() -> DiagRow {
        let mcpBin = Self.preferredMCPBinary()
        let locations = Self.mcpRegisteredLocations(name: "beamhop")
        if !locations.isEmpty {
            return DiagRow(name: "Claude MCP registration", state: .ok,
                           detail: "Registered (\(locations.joined(separator: ", ")))",
                           fixTitle: nil, fix: nil)
        }
        let claudePath = whichClaude()
        if let claudePath, let mcpBin {
            // Week 2 close-out (2026-10-19): real one-click registration via `claude mcp add`.
            return DiagRow(name: "Claude MCP registration", state: .warn,
                           detail: "Not registered — one-click register below",
                           fixTitle: "Register now",
                           fix: { Self.registerMCP(claude: claudePath, mcpBinary: mcpBin) })
        }
        let desktopInstalled = Self.desktopConfigURLs()
            .contains { FileManager.default.fileExists(atPath: $0.path) }
            || FileManager.default.fileExists(atPath: "/Applications/Claude.app")
        if desktopInstalled, let mcpBin {
            return DiagRow(name: "Claude MCP registration", state: .warn,
                           detail: "Not registered in Claude Desktop — one-click register below",
                           fixTitle: "Register now",
                           fix: { Self.registerMCPInDesktop(name: "beamhop", mcpBinary: mcpBin) })
        }
        // Fallback (dev `swift run` without an app bundle, or no Claude product at all).
        let bin = mcpBin ?? "<absolute path to BeamhopMCP>"
        return DiagRow(name: "Claude MCP registration", state: .warn,
                       detail: "No Claude Code CLI or Claude Desktop detected — install either to enable MCP write-back",
                       fixTitle: "Copy registration command",
                       fix: {
                           let cmd = "claude mcp add beamhop -s user -- \(bin) --db \(AppPaths.databaseURL.path)"
                           NSPasteboard.general.clearContents()
                           NSPasteboard.general.setString(cmd, forType: .string)
                       })
    }

    private func coworkRow() -> DiagRow {
        DiagRow(name: "Claude Cowork integration",
                state: .todo,
                detail: "Phase 1.5 — mechanism confirmed (.mcpb / claude_desktop_config.json), end-to-end pending",
                fixTitle: nil, fix: nil)
    }

    private func chatGPTRow() -> DiagRow {
        let appPath = "/Applications/ChatGPT.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            return DiagRow(name: "ChatGPT Desktop AX",
                           state: .warn, detail: "ChatGPT Desktop not installed",
                           fixTitle: nil, fix: nil)
        }
        let ver = (Bundle(path: appPath)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let known = ver == knownChatGPTVersion
        return DiagRow(name: "ChatGPT Desktop AX",
                       state: known ? .ok : .warn,
                       detail: known ? "v\(ver) (in the compatibility matrix)"
                                     : "v\(ver) is outside the verified matrix (v\(knownChatGPTVersion)) — re-test likely",
                       fixTitle: nil, fix: nil)
    }

    private func hotkeyRow() -> DiagRow {
        if hotkeyConflicts.isEmpty {
            return DiagRow(name: "Global hotkeys", state: .ok, detail: "Registered", fixTitle: nil, fix: nil)
        }
        return DiagRow(name: "Global hotkeys",
                       state: .warn,
                       detail: "Conflicts: \(hotkeyConflicts.joined(separator: ", ")) (possibly taken by Spotlight etc.)",
                       fixTitle: nil, fix: nil)   // 改键 UI: Week 1 Settings(后续)
    }

    // MARK: helpers

    /// `claude mcp add beamhop -s user -- <bundle MCP> --db <inbox>` off the main thread;
    /// outcome surfaces via Notifier and the row re-evaluates on the next window open.
    private static func registerMCP(claude: String, mcpBinary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: claude)
            p.arguments = ["mcp", "add", "beamhop", "-s", "user", "--", mcpBinary,
                           "--db", AppPaths.databaseURL.path]
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            // GUI apps get a minimal PATH; the claude CLI (and the node it may spawn) lives
            // in one of these.
            env["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.claude/local",
                           "\(home)/.local/bin", env["PATH"] ?? ""].joined(separator: ":")
            p.environment = env
            do {
                try p.run()
                p.waitUntilExit()
                let cliConfig = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude.json")
                let ok = p.terminationStatus == 0 && mcpServerRegistered(name: "beamhop", in: cliConfig)
                DispatchQueue.main.async {
                    if ok {
                        Notifier.success(L10n.s("Beamhop MCP registered"),
                                         L10n.s("Restart Claude Code sessions to pick it up"))
                    } else {
                        Notifier.error(L10n.s("Registration failed"),
                                       "claude mcp add exited \(p.terminationStatus)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    Notifier.error(L10n.s("Registration failed"), String(describing: error))
                }
            }
        }
    }

    /// The BeamhopMCP binary shipped next to the app executable (nil under `swift run`).
    private static func bundledMCPBinary() -> String? {
        let p = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/BeamhopMCP").path
        return FileManager.default.isExecutableFile(atPath: p) ? p : nil
    }

    private func whichClaude() -> String? {
        if let p = which("claude") { return p }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in ["/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.claude/local/claude", "\(home)/.local/bin/claude",
                          "\(home)/.npm-global/bin/claude"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Registration homes for Claude Desktop: both deployment variants' config files
    /// (this machine runs the 3p deployment, where `Claude/` edits are silently ignored).
    private static func desktopConfigURLs() -> [URL] {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return ["Claude", "Claude-3p"].map {
            appSupport.appendingPathComponent("\($0)/claude_desktop_config.json")
        }
    }

    /// Human-readable locations where the named MCP server is already registered.
    private static func mcpRegisteredLocations(name: String) -> [String] {
        var found: [String] = []
        let cliConfig = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        if mcpServerRegistered(name: name, in: cliConfig) { found.append("Claude Code") }
        for url in desktopConfigURLs() where mcpServerRegistered(name: name, in: url) {
            found.append("Claude Desktop (\(url.deletingLastPathComponent().lastPathComponent))")
        }
        return found
    }

    /// Stable installed path survives repacks (NEVER register a `.build/` or `dist/` binary);
    /// fall back to the copy bundled next to the app executable (nil under `swift run`).
    private static func preferredMCPBinary() -> String? {
        let stable = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/beamhop/bin/BeamhopMCP").path
        if FileManager.default.isExecutableFile(atPath: stable) { return stable }
        return bundledMCPBinary()
    }

    /// Register into every existing claude_desktop_config.json (creating the current
    /// deployment's file when none exists). Claude Desktop must be restarted to pick it up.
    private static func registerMCPInDesktop(name: String, mcpBinary: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var urls = desktopConfigURLs()
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if urls.isEmpty { urls = [desktopConfigURLs()[1]] }   // Claude-3p = current deployment
            var failures = 0
            for url in urls where !registerMCPInConfig(url: url, name: name, mcpBinary: mcpBinary) {
                failures += 1
            }
            let ok = failures == 0 && !mcpRegisteredLocations(name: name).isEmpty
            DispatchQueue.main.async {
                if ok {
                    Notifier.success(L10n.s("Beamhop MCP registered"),
                                     L10n.s("Restart Claude Desktop to pick it up"))
                } else {
                    Notifier.error(L10n.s("Registration failed"),
                                   "\(failures) config file(s) could not be updated")
                }
            }
        }
    }

    /// Merge the server entry into one Desktop config file, preserving every existing key.
    private static func registerMCPInConfig(url: URL, name: String, mcpBinary: String) -> Bool {
        let json = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        servers[name] = ["command": mcpBinary, "args": ["--db", AppPaths.databaseURL.path]]
        var out = json
        out["mcpServers"] = servers
        guard let data = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted])
        else { return false }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private static func mcpServerRegistered(name: String, in url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers[name] != nil
    }

    private func which(_ tool: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for p in paths {
            let candidate = String(p) + "/" + tool
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
