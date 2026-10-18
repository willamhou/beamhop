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
        guard mcpRegistered() else { return L10n.s("Beamhop MCP is not registered with Claude Code (register it from the Diagnostics window)") }
        guard let target = TerminalLocator.locate() else { return L10n.s("No running terminal found (Terminal/iTerm/…)") }

        guard AppActivator.focus(target.app, bundleID: target.bundleID) else {
            return L10n.s("Could not bring the terminal to the front")
        }

        let trigger = PromptRenderer.claudeCodeTrigger(capture, userNote: userNote)
        // codex: auto-Enter ONLY when the located terminal was the frontmost one AND a claude
        // process is likely running — otherwise we could send ⏎ into the wrong window. When unsure,
        // paste and let the user press Enter.
        let autoEnter = target.wasFrontmost && TerminalLocator.claudeLikelyRunning()
        do {
            try ClipboardService.safePaste(trigger, pressEnter: autoEnter)
        } catch {
            return L10n.s("Clipboard could not be protected — automatic paste aborted (paste manually)")
        }
        if !autoEnter {
            Notifier.info(L10n.s("Trigger prompt pasted to the terminal"), L10n.s("Confirm it is the right terminal window, then press Enter to send"))
        }
        return nil
    }
}
