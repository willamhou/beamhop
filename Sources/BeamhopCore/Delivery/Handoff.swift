import Foundation

/// One deliberate handoff. A batch is rendered once, never pasted item by item.
public struct Handoff: Sendable {
    public struct Item: Sendable {
        public let capture: Capture
        public let note: String?
        public init(capture: Capture, note: String? = nil) {
            self.capture = capture
            self.note = note
        }
    }
    public let items: [Item]
    public let editedText: String?
    public init(items: [Item], editedText: String? = nil) { self.items = items; self.editedText = editedText }

    public var markdown: String {
        editedText ?? render { PromptRenderer.fullMarkdown($0.capture, userNote: $0.note) }
    }

    public var claudeTrigger: String {
        // An MCP fetch of the original capture would silently undo the user's edits.
        editedText ?? render { PromptRenderer.claudeCodeTrigger($0.capture, userNote: $0.note) }
    }

    private func render(_ body: (Item) -> String) -> String {
        guard items.count > 1 else { return items.first.map(body) ?? "" }
        return items.enumerated().map { index, item in
            "## Material \(index + 1)\n\n" + body(item)
        }.joined(separator: "\n\n---\n\n")
    }
}

public extension DeliveryTarget {
    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .chatgptDesktop: return "ChatGPT"
        case .kimiWork: return "Kimi Work"
        case .clipboard: return L10n.s("Clipboard")
        case .cowork: return L10n.s("Cowork → clipboard")
        }
    }

    var handoffAction: String {
        switch self {
        case .clipboard, .cowork: return L10n.s("Copy materials")
        default: return L10n.f("Continue in %@", displayName)
        }
    }

    var handoffDetail: String {
        switch self {
        case .clipboard, .cowork: return L10n.s("Copy once, then paste where you need it")
        case .claudeCode: return L10n.s("Copy text, then paste into the Claude Code input")
        default: return L10n.s("Current window · review before sending")
        }
    }
}
