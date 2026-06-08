import Foundation
import BeamhopCore

/// Renders the text injected into a target (spec §7.6). Two flavors:
///  - trigger: a short prompt telling an MCP-aware agent to pull the capture itself (§7.3 — saves
///    tokens; we DON'T paste the body).
///  - full: the whole capture as markdown, for clipboard handoff where there's no MCP channel.
enum PromptRenderer {
    /// Claude Code trigger: agent calls fetch_capture itself via the Beamhop MCP server.
    static func claudeCodeTrigger(_ capture: Capture, userNote: String?) -> String {
        let note = (userNote?.isEmpty == false) ? "。\(userNote!)" : ""
        return "用 Beamhop MCP 的 fetch_capture('\(capture.id)') 拿我刚抓的上下文\(note)"
    }

    /// Full markdown for clipboard handoff (no MCP). Body truncated for paste; DB keeps full.
    static func fullMarkdown(_ capture: Capture, userNote: String?, maxBody: Int = 100_000) -> String {
        var out = ""
        out += "Source: \(capture.appName)"
        if let url = capture.url { out += " · \(url)" }
        out += "\n"
        if let title = capture.windowTitle, !title.isEmpty { out += "Title: \(title)\n" }
        if let sel = capture.selectedText, !sel.isEmpty {
            out += "\n<selected>\n\(truncate(sel, maxBody))\n</selected>\n"
        }
        if let body = capture.extractedBody, !body.isEmpty {
            out += "\n<body>\n\(truncate(body, maxBody))\n</body>\n"
        }
        if let note = userNote, !note.isEmpty { out += "\n\(note)\n" }
        return out
    }

    private static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "\n…[truncated; full content in Beamhop Inbox]"
    }
}
