import AppKit
import Foundation
import BeamhopCore

/// Golden-path delivery to Claude Code (spec §7.3): capture is already in the Inbox + exposed by
/// the Beamhop MCP server; we AX-paste a short trigger prompt into a terminal so Claude Code
/// pulls the capture itself via fetch_capture. NOT pasting the body (§7.3 — saves tokens).
enum ClaudeCodeDelivery {
    /// Precondition check: is the Beamhop MCP server registered (user scope)? (S1)
    static func mcpRegistered() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["beamhop"] != nil
    }

    /// Returns nil on success, or a user-facing failure reason (caller falls back to clipboard).
    static func deliver(_ capture: Capture, userNote: String?) -> String? {
        guard mcpRegistered() else { return "Claude Code 的 Beamhop MCP 未注册(去诊断面板一键注册)" }
        guard let target = TerminalLocator.locate() else { return "未找到运行中的终端(Terminal/iTerm/…)" }

        // bring the terminal forward + give it a moment to focus
        target.app.activate(options: [.activateAllWindows])
        var front = false
        for _ in 0..<15 {
            usleep(80_000)
            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == target.bundleID { front = true; break }
            target.app.activate(options: [.activateAllWindows])
        }
        guard front else { return "无法把终端切到前台" }

        let trigger = PromptRenderer.claudeCodeTrigger(capture, userNote: userNote)
        // codex review: only auto-Enter when we're confident claude is running; else paste, let user confirm.
        let autoEnter = TerminalLocator.claudeLikelyRunning()
        do {
            try ClipboardService.safePaste(trigger, pressEnter: autoEnter)
        } catch {
            return "剪贴板无法保护,已放弃自动粘贴(请手动粘贴)"
        }
        if !autoEnter {
            Notifier.info("已粘贴触发 prompt 到终端", "未检测到运行中的 Claude Code,请你按回车确认发送")
        }
        return nil
    }
}
