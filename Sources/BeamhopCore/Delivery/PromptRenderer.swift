import Foundation

/// Renders the text injected into a target (spec §7.6). Two flavors:
///  - trigger: a short prompt telling an MCP-aware agent to pull the capture itself (§7.3 — saves
///    tokens; we DON'T paste the body).
///  - full: the whole capture as markdown, for clipboard handoff where there's no MCP channel.
public enum PromptRenderer {
    /// MCP-aware agent trigger: agent calls fetch_capture itself via the Beamhop MCP server
    /// (§7.3 — saves tokens; we DON'T paste the body), then writes its conclusion back via
    /// save_result so the loop closes into provenance-linked shared memory
    /// (memory-mcp-decision spec 2026-10-18 §4).
    public static func mcpTrigger(_ capture: Capture, userNote: String?, agent: String) -> String {
        let note = (userNote?.isEmpty == false) ? "。\(userNote!)" : ""
        return "用 Beamhop MCP 的 fetch_capture('\(capture.id)') 拿我刚抓的上下文\(note)。"
            + "处理完后调用 save_result(origin_capture_id='\(capture.id)', content=你的结论, agent='\(agent)')"
            + " 把结论写回 Beamhop，形成可追溯的共享记忆"
    }

    /// Claude Code trigger (its MCP registration and tool names are the Beamhop defaults).
    public static func claudeCodeTrigger(_ capture: Capture, userNote: String?) -> String {
        mcpTrigger(capture, userNote: userNote, agent: "claude_code")
    }

    /// Full markdown for clipboard handoff (no MCP). Body truncated for paste; DB keeps full.
    public static func fullMarkdown(_ capture: Capture, userNote: String?, maxBody: Int = 100_000) -> String {
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

    static func truncate(_ s: String, _ max: Int) -> String {
        s.count <= max ? s : String(s.prefix(max)) + "\n…[truncated; full content in Beamhop Inbox]"
    }
}
