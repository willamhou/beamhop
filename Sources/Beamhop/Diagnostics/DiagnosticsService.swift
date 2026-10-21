import Foundation
import AppKit
import BeamhopCore

typealias DiagState = DiagnosticStatus
extension DiagnosticStatus {
    var symbol: String {
        switch self { case .ok: return "✅"; case .fail: return "❌"; case .warn: return "⚠️"; case .todo: return "🚧" }
    }
}

struct DiagRow: Identifiable {
    let id: DiagnosticCheckID
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

    /// Never export row names/details/fix commands: they can contain paths or free text.
    static func report(rows: [DiagRow], build: BuildInfo) -> DiagnosticReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return DiagnosticReport(build: build, macOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                                runtimeArchitecture: architecture,
                                checks: rows.map { DiagnosticCheck(id: $0.id, status: $0.state) })
    }

    private func accessibilityRow() -> DiagRow {
        let ok = permissions.accessibility() == .granted
        return DiagRow(id: .accessibility, name: "Accessibility permission",
                       state: ok ? .ok : .fail,
                       detail: ok ? "Granted" : "Not granted — capture depends on it",
                       fixTitle: ok ? nil : "Open System Settings",
                       fix: ok ? nil : { permissions.openAccessibilitySettings() })
    }

    private func screenRecordingRow() -> DiagRow {
        let ok = permissions.preflightScreenRecording() == .granted
        return DiagRow(id: .screenRecording, name: "Screen Recording permission",
                       state: ok ? .ok : .warn,
                       detail: ok ? "Granted" : "Not granted (only screenshots need it — skippable)",
                       fixTitle: ok ? nil : "Open System Settings",
                       fix: ok ? nil : { permissions.openScreenRecordingSettings() })
    }

    private func chromeHostRow() -> DiagRow {
        // Packaging exists; this row does not claim a live extension/host round-trip.
        DiagRow(id: .chromeHost, name: "Chrome native messaging host",
                state: .todo,
                detail: "Host is packaged; browser manifest and live bridge require separate verification",
                fixTitle: nil, fix: nil)
    }

    private func claudeCodeMCPRow() -> DiagRow {
        let registered = Self.mcpServerRegistered(name: "beamhop")
        let claudePath = whichClaude()
        let mcpBin = Self.bundledMCPBinary()
        let state: DiagState = registered ? .ok : (claudePath != nil ? .warn : .fail)
        let detail = registered ? "Registered (top-level mcpServers in ~/.claude.json)"
            : (claudePath != nil ? "Not registered — one-click register below"
                                 : "No `claude` CLI detected (install Claude Code first)")
        let fixTitle: String?
        let fix: (() -> Void)?
        if registered {
            fixTitle = nil; fix = nil
        } else if let claudePath, let mcpBin {
            // Week 2 close-out (2026-10-19): real one-click registration via `claude mcp add`.
            fixTitle = "Register now"
            fix = { Self.registerMCP(claude: claudePath, mcpBinary: mcpBin) }
        } else {
            // Fallback (dev `swift run` without an app bundle, or missing claude): copy the command.
            let bin = mcpBin ?? "<absolute path to BeamhopMCP>"
            fixTitle = "Copy registration command"
            fix = {
                let cmd = "claude mcp add beamhop -s user -- \(bin) --db \(AppPaths.databaseURL.path)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cmd, forType: .string)
            }
        }
        return DiagRow(id: .claudeMCP, name: "Claude Code MCP registration", state: state, detail: detail,
                       fixTitle: fixTitle, fix: fix)
    }

    private func coworkRow() -> DiagRow {
        DiagRow(id: .cowork, name: "Claude Cowork integration",
                state: .todo,
                detail: "Phase 1.5 — mechanism confirmed (.mcpb / claude_desktop_config.json), end-to-end pending",
                fixTitle: nil, fix: nil)
    }

    private func chatGPTRow() -> DiagRow {
        let appPath = "/Applications/ChatGPT.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            return DiagRow(id: .chatGPT, name: "ChatGPT Desktop AX",
                           state: .warn, detail: "ChatGPT Desktop not installed",
                           fixTitle: nil, fix: nil)
        }
        let ver = (Bundle(path: appPath)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let known = ver == knownChatGPTVersion
        return DiagRow(id: .chatGPT, name: "ChatGPT Desktop AX",
                       state: known ? .ok : .warn,
                       detail: known ? "v\(ver) (in the compatibility matrix)"
                                     : "v\(ver) is outside the verified matrix (v\(knownChatGPTVersion)) — re-test likely",
                       fixTitle: nil, fix: nil)
    }

    private func hotkeyRow() -> DiagRow {
        if hotkeyConflicts.isEmpty {
            return DiagRow(id: .hotkeys, name: "Global hotkeys", state: .ok, detail: "Registered", fixTitle: nil, fix: nil)
        }
        return DiagRow(id: .hotkeys, name: "Global hotkeys",
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
                let ok = p.terminationStatus == 0 && mcpServerRegistered(name: "beamhop")
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

    private static func mcpServerRegistered(name: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
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
