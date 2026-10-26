import Foundation
import GRDB

/// An agent-reported conclusion for one frozen Hop attempt, not a transport receipt.
public struct HandoffResult: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "handoff_results"
    public var id: String
    public var handoffID: String
    public var agent: String
    public var sessionID: String?
    public var content: String
    public var createdAt: Int64
    enum CodingKeys: String, CodingKey {
        case id, agent, content
        case handoffID = "handoff_id", sessionID = "session_id", createdAt = "created_at"
    }
    public init(id: String = ULID.resultID(), handoffID: String, agent: String, sessionID: String? = nil,
                content: String, createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id; self.handoffID = handoffID; self.agent = agent
        self.sessionID = sessionID; self.content = content; self.createdAt = createdAt
    }
}

/// MCP's allowlisted view. Never encode HopRecord itself: it contains private originals
/// and local attachment paths that were not included in the handoff.
public struct HandoffPayload: Codable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let transportStatus: HopRecord.Status
    public init(record: HopRecord) {
        id = record.id; text = record.textFallback; transportStatus = record.status
    }
}
