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
        return DiagRow(name: "Accessibility 权限",
                       state: ok ? .ok : .fail,
                       detail: ok ? "已授权" : "未授权 —— 抓取功能依赖它",
                       fixTitle: ok ? nil : "打开系统设置",
                       fix: ok ? nil : { permissions.openAccessibilitySettings() })
    }

    private func screenRecordingRow() -> DiagRow {
        let ok = permissions.preflightScreenRecording() == .granted
        return DiagRow(name: "Screen Recording 权限",
                       state: ok ? .ok : .warn,
                       detail: ok ? "已授权" : "未授权(仅截图功能需要,可跳过)",
                       fixTitle: ok ? nil : "打开系统设置",
                       fix: ok ? nil : { permissions.openScreenRecordingSettings() })
    }

    private func chromeHostRow() -> DiagRow {
        // Week 1 has no host binary yet → fixed 🚧 (do NOT infer ✅ from a stray manifest). codex.
        DiagRow(name: "Chrome native messaging host",
                state: .todo,
                detail: "Week 2 实现(host 二进制 + manifest 写入)",
                fixTitle: nil, fix: nil)
    }

    private func claudeCodeMCPRow() -> DiagRow {
        let registered = mcpServerRegistered(name: "beamhop")
        let claudeOnPath = which("claude") != nil
        let state: DiagState = registered ? .ok : (claudeOnPath ? .warn : .fail)
        let detail = registered ? "已注册(~/.claude.json 顶层 mcpServers)"
            : (claudeOnPath ? "未注册 —— Week 2 出 host 后一键注册" : "未检测到 `claude` CLI")
        return DiagRow(name: "Claude Code MCP 注册",
                       state: state,
                       detail: detail,
                       // Week 1: command preview only (host binary is Week 2). codex.
                       fixTitle: registered ? nil : "复制注册命令",
                       fix: registered ? nil : {
                           // Week 2: command preview incl. --db (real one-click register is a follow-up).
                           let cmd = "claude mcp add beamhop -s user -- <BeamhopMCP 绝对路径> --db \(AppPaths.databaseURL.path)"
                           NSPasteboard.general.clearContents()
                           NSPasteboard.general.setString(cmd, forType: .string)
                       })
    }

    private func coworkRow() -> DiagRow {
        DiagRow(name: "Claude Cowork 集成",
                state: .todo,
                detail: "Phase 1.5 —— 机制已确认(.mcpb / claude_desktop_config.json),待端到端验证",
                fixTitle: nil, fix: nil)
    }

    private func chatGPTRow() -> DiagRow {
        let appPath = "/Applications/ChatGPT.app"
        guard FileManager.default.fileExists(atPath: appPath) else {
            return DiagRow(name: "ChatGPT Desktop AX",
                           state: .warn, detail: "未安装 ChatGPT Desktop",
                           fixTitle: nil, fix: nil)
        }
        let ver = (Bundle(path: appPath)?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        let known = ver == knownChatGPTVersion
        return DiagRow(name: "ChatGPT Desktop AX",
                       state: known ? .ok : .warn,
                       detail: known ? "v\(ver)(在兼容矩阵内)"
                                     : "v\(ver) 不在已验证矩阵(v\(knownChatGPTVersion))—— 可能需复测",
                       fixTitle: nil, fix: nil)
    }

    private func hotkeyRow() -> DiagRow {
        if hotkeyConflicts.isEmpty {
            return DiagRow(name: "全局快捷键", state: .ok, detail: "已注册", fixTitle: nil, fix: nil)
        }
        return DiagRow(name: "全局快捷键",
                       state: .warn,
                       detail: "冲突:\(hotkeyConflicts.joined(separator: ", "))(可能被 Spotlight 等占用)",
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
