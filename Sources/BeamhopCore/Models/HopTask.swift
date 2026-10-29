import Foundation

/// Explicit local task identity, not a project name or an external conversation.
public struct HopTask: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public init(title: String) {
        id = UUID().uuidString
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public var displayLabel: String { title + " · " + String(id.prefix(8)) }
}

/// User-editable material; source IDs identify selection, not an unedited quotation.
public struct HopRelayContext: Codable, Equatable, Sendable {
    public var text: String
    public let sourceHandoffID: String?
    public let sourceResultID: String?
    public init(text: String, sourceHandoffID: String? = nil, sourceResultID: String? = nil) {
        self.text = text
        self.sourceHandoffID = sourceHandoffID
        self.sourceResultID = sourceResultID
    }
    public var outgoingText: String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        var parts = ["--- Editable relay context · agent claims are unverified ---"]
        if let sourceHandoffID { parts.append("Selected from handoff: \(sourceHandoffID)") }
        if let sourceResultID { parts.append("Selected from result: \(sourceResultID)") }
        parts.append(text)
        return parts.joined(separator: "\n")
    }
}
