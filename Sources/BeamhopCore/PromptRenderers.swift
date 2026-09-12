import Foundation

public protocol PromptRenderer {
    func render(_ capture: Capture, userNote: String?) -> String
}

public struct ClaudeCodeRenderer: PromptRenderer, Sendable {
    public init() {}

    public func render(_ capture: Capture, userNote: String? = nil) -> String {
        let instruction = effectiveNote(userNote, capture: capture)
        var prompt = "Use the Beamhop MCP fetch_capture tool to load capture '\(capture.id)' and treat it as user-provided context."
        if let instruction {
            prompt += " User request: \(instruction)"
        }
        return prompt
    }
}

public struct ClaudeCoworkRenderer: PromptRenderer, Sendable {
    public init() {}

    public func render(_ capture: Capture, userNote: String? = nil) -> String {
        let instruction = effectiveNote(userNote, capture: capture)
        var prompt = "Fetch Beamhop capture '\(capture.id)' with fetch_capture before responding."
        if let instruction {
            prompt += " User request: \(instruction)"
        }
        return prompt
    }
}

/// A self-contained payload for targets without MCP support, including
/// ChatGPT Desktop and the universal clipboard fallback.
public struct SelfContainedMarkdownRenderer: PromptRenderer, Sendable {
    public init() {}

    public func render(_ capture: Capture, userNote: String? = nil) -> String {
        var sections: [String] = []
        let sourceLocation = capture.url?.absoluteString ?? capture.appBundleID
        sections.append("Source: \(capture.appName) · \(sourceLocation)")
        if let title = nonEmpty(capture.windowTitle) {
            sections.append("Title: \(title)")
        }
        if let selectedText = nonEmpty(capture.selectedText) {
            sections.append("<selected>\n\(selectedText)\n</selected>")
        }
        if let body = nonEmpty(capture.extractedBody) {
            sections.append("<body>\n\(body)\n</body>")
        }
        if let screenshotPath = nonEmpty(capture.screenshotPath) {
            sections.append("Screenshot: \(screenshotPath)")
        }
        if let instruction = effectiveNote(userNote, capture: capture) {
            sections.append("User request:\n\(instruction)")
        }

        var flags: [String] = [
            "capture_id=\(capture.id)",
            "method=\(capture.provenance.captureMethod.rawValue)",
            "source_app_version=\(capture.provenance.appVersion ?? "unknown")"
        ]
        if capture.provenance.isPrivate { flags.append("private=true") }
        if capture.provenance.isTruncated { flags.append("truncated=true") }
        sections.append("Provenance: " + flags.joined(separator: " · "))
        return sections.joined(separator: "\n\n")
    }
}

public typealias ChatGPTDesktopRenderer = SelfContainedMarkdownRenderer
public typealias ClipboardRenderer = SelfContainedMarkdownRenderer

private func effectiveNote(_ override: String?, capture: Capture) -> String? {
    nonEmpty(override) ?? nonEmpty(capture.userNote)
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
