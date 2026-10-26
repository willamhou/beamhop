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
        if target == .clipboard || target == .cowork { return L10n.s("Paste into the app yourself") }
        return L10n.s(session == .currentWindow ? "Current window" : "New session · create in app")
    }
}

public struct HopDraft: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID().uuidString
    public var materials: [HopMaterial]
    public var instruction: String
    public var route: HopRoute
    public var requestsResultReturn: Bool
    public init(materials: [HopMaterial], instruction: String = "", route: HopRoute = .init(), requestsResultReturn: Bool = false) {
        self.materials = materials; self.instruction = instruction; self.route = route
        self.requestsResultReturn = requestsResultReturn
    }
    enum CodingKeys: String, CodingKey { case id, materials, instruction, route, requestsResultReturn }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        materials = try values.decode([HopMaterial].self, forKey: .materials)
        instruction = try values.decode(String.self, forKey: .instruction)
        route = try values.decode(HopRoute.self, forKey: .route)
        requestsResultReturn = try values.decodeIfPresent(Bool.self, forKey: .requestsResultReturn) ?? false
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
        outgoingText + attachmentReminder
    }
    fileprivate var attachmentReminder: String {
        attachments.isEmpty ? "" : "\n\n" + L10n.s("Attachments to add manually:") + "\n" + attachments.map(\.name).joined(separator: "\n")
    }
}

public struct HopRecord: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case preparing, prepared, copied, failed }
    public let id: String
    public let draft: HopDraft
    public var status: Status
    public var detail: String?
    /// Frozen Pocket inputs for a combined handoff. Older receipts decode this as nil.
    public var pocketSources: [HopDraft]?
    /// Missing on pre-identity backups: never imply metadata was part of their payload.
    public let envelopeVersion: Int?
    /// Freeze localized outgoing strings too: an MCP process or a later app language
    /// must not regenerate a different payload from the immutable draft.
    private let frozenOutgoingText: String?
    private let frozenAttachmentReminder: String?
    public init(draft: HopDraft, status: Status = .preparing, detail: String? = nil) {
        let id = UUID().uuidString
        self.id = id
        self.draft = draft; self.status = status; self.detail = detail
        self.envelopeVersion = 1
        self.frozenOutgoingText = Self.makeOutgoingText(draft: draft, id: id)
        self.frozenAttachmentReminder = draft.attachmentReminder
    }
    public var acceptsResultReturn: Bool { envelopeVersion == 1 && draft.requestsResultReturn }
    public var outgoingText: String {
        guard envelopeVersion == 1 else { return draft.outgoingText }
        return frozenOutgoingText ?? Self.makeOutgoingText(draft: draft, id: id)
    }
    private static func makeOutgoingText(draft: HopDraft, id: String) -> String {
        var metadata = "--- Beamhop handoff ---\nHandoff ID: \(id)"
        if draft.requestsResultReturn {
            metadata += "\nOptional conclusion return: if the Beamhop MCP tool save_handoff_result is available, "
                + "you may call it with handoff_id='\(id)', content=your conclusion, agent=your identifier. "
                + "Use the edited materials above, not the original captures. "
                + "If the tool is unavailable, answer normally; do not claim a result was saved. "
                + "A returned conclusion is not independent proof of task completion."
        }
        return [draft.outgoingText, metadata].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    public var textFallback: String {
        outgoingText + (envelopeVersion == 1 ? frozenAttachmentReminder ?? draft.attachmentReminder : draft.attachmentReminder)
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
