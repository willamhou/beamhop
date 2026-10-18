import Foundation
import GRDB

/// An agent-written conclusion about a Capture (memory-mcp-decision spec 2026-10-18 §2.2).
/// Maps to the `results` table. Distinct from Delivery: a Delivery records the transport
/// attempt ("what we sent, where, did it arrive"), a CaptureResult is the agent's own
/// write-back of what it concluded ("what the agent gave back").
///
/// Append-only by design: insert-only, no soft delete — a conclusion is an immutable event
/// (evidence-gate baseline, same policy as captures' auditability).
public struct CaptureResult: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "results"

    public var id: String                 // "res_<ulid>"
    public var originCaptureID: String    // FK -> captures(id), what this concludes about
    public var agent: String              // free-form writer id: claude_code / codex / kimi / …
    public var sessionID: String?         // writer-side session identifier (optional)
    public var content: String            // conclusion text, verbatim — not distilled
    public var createdAt: Int64           // unix ms

    enum CodingKeys: String, CodingKey {
        case id
        case originCaptureID = "origin_capture_id"
        case agent
        case sessionID = "session_id"
        case content
        case createdAt = "created_at"
    }

    public init(
        id: String = ULID.resultID(),
        originCaptureID: String,
        agent: String,
        sessionID: String? = nil,
        content: String,
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.originCaptureID = originCaptureID
        self.agent = agent
        self.sessionID = sessionID
        self.content = content
        self.createdAt = createdAt
    }
}
