import Foundation

/// The original capture is evidence. Only `text` is included in a handoff.
public struct HopMaterial: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case text, file, image }
    public var id = UUID().uuidString
    public var kind: Kind
    public var name: String
    public var text: String
    public let original: Capture?
    public var localPath: String?
    public var byteCount: Int64?

    public init(capture: Capture) {
        kind = .text; name = capture.appName; original = capture
        text = capture.selectedText ?? capture.extractedBody ?? capture.windowTitle ?? ""
    }
    public init(text: String) {
        kind = .text; name = "Added text"; self.text = text; original = nil
    }
    public init(name: String, path: String, image: Bool, bytes: Int64) {
        kind = image ? .image : .file; self.name = name; text = ""
        original = nil; localPath = path; byteCount = bytes
    }
    public var originalText: String? { original.map { $0.selectedText ?? $0.extractedBody ?? $0.windowTitle ?? "" } }
    public var isEdited: Bool { originalText.map { $0 != text } ?? false }
}

/// An app/window intent, not a fabricated external conversation address.
public struct HopRoute: Codable, Equatable, Sendable {
    public enum Session: String, Codable, Sendable { case currentWindow, newInApp }
    public var target: DeliveryTarget?
    public var project: String
    public var session: Session
    public init(target: DeliveryTarget? = nil, project: String = "", session: Session = .currentWindow) {
        self.target = target; self.project = project; self.session = session
    }
    public var sessionLabel: String {
        if target == nil { return L10n.s("Keep on this Mac") }
        return L10n.s(session == .currentWindow ? "Current window" : "New session · create in app")
    }
}

public struct HopDraft: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var materials: [HopMaterial]
    public var instruction: String
    public var route: HopRoute
    public init(materials: [HopMaterial], instruction: String = "", route: HopRoute = .init()) {
        self.materials = materials; self.instruction = instruction; self.route = route
    }
    public var hasContent: Bool { !materials.isEmpty || !instruction.isEmpty }
    public var attachments: [HopMaterial] { materials.filter { $0.kind != .text } }
    public var hasNativeCommand: Bool { instruction.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") }
    /// Instruction stays literal and first, including slash commands and newlines.
    public var outgoingText: String {
        ([instruction].filter { !$0.isEmpty } + materials.filter { $0.kind == .text }.map { material in
            let source = material.original.map { [$0.appName, $0.url].compactMap { $0 }.joined(separator: " · ") } ?? L10n.s("Added text")
            return "Source: \(source)\n\(material.text)"
        }).joined(separator: "\n\n")
    }
    public var textFallback: String {
        outgoingText + (attachments.isEmpty ? "" : "\n\n" + L10n.s("Attachments to add manually:") + "\n" + attachments.map(\.name).joined(separator: "\n"))
    }
}

public struct HopRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case preparing, prepared, copied, failed }
    public var id = UUID().uuidString
    public let draft: HopDraft
    public var status: Status
    public var detail: String?
    public init(draft: HopDraft, status: Status = .preparing, detail: String? = nil) {
        self.draft = draft; self.status = status; self.detail = detail
    }
    public var label: String {
        switch status {
        case .preparing: return L10n.s("Preparing · not sent")
        case .prepared: return L10n.s("Draft prepared · not sent")
        case .copied: return L10n.s("Text copied · not sent")
        case .failed: return L10n.s("Handoff incomplete · backup kept")
        }
    }
}
