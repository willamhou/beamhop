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

    private func claudeCodeMCPRow() -> DiagRow {
        let registered = mcpServerRegistered(name: "beamhop")
        let claudeOnPath = which("claude") != nil
        let state: DiagState = registered ? .ok : (claudeOnPath ? .warn : .fail)
        let detail = registered ? "Registered (top-level mcpServers in ~/.claude.json)"
            : (claudeOnPath ? "Not registered — one-click registration ships with the Week 2 host" : "No `claude` CLI detected")
        return DiagRow(name: "Claude Code MCP registration",
                       state: state,
                       detail: detail,
                       // Week 1: command preview only (host binary is Week 2). codex.
                       fixTitle: registered ? nil : "Copy registration command",
                       fix: registered ? nil : {
                           // Week 2: command preview incl. --db (real one-click register is a follow-up).
                           let cmd = "claude mcp add beamhop -s user -- <absolute path to BeamhopMCP> --db \(AppPaths.databaseURL.path)"
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

    private func mcpServerRegistered(name: String) -> Bool {
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
