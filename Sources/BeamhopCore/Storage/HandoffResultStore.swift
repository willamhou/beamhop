import Foundation
import GRDB

/// The app owns schema and frozen records. This module only reads records and appends
/// conclusions; external writers never update receipt status or consume a draft.
public final class HandoffResultStore {
    private let queue: DatabaseQueue
    public init(_ queue: DatabaseQueue) { self.queue = queue }

    public static func open(path: URL) throws -> HandoffResultStore {
        let queue = try Database.openExistingReadWrite(path: path)
        guard try queue.read({ db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('hop_records', 'handoff_results')")
        }) == 2 else { throw DatabaseError.schemaOutdated }
        return HandoffResultStore(queue)
    }

    public enum ReturnError: LocalizedError, Equatable {
        case unavailableHandoff, emptyContent, emptyAgent
        public var errorDescription: String? {
            switch self {
            case .unavailableHandoff: return "Handoff not found or conclusion return was not enabled."
            case .emptyContent: return "A nonblank conclusion is required."
            case .emptyAgent: return "A nonblank agent identifier is required."
            }
        }
    }

    private static func record(_ db: GRDB.Database, id: String) throws -> HopRecord? {
        try Data.fetchOne(db, sql: "SELECT payload FROM hop_records WHERE id = ?", arguments: [id])
            .map { try JSONDecoder().decode(HopRecord.self, from: $0) }
    }
    private static func returnableRecord(_ db: GRDB.Database, id: String) throws -> HopRecord {
        guard let record = try record(db, id: id), record.id == id, record.acceptsResultReturn else {
            throw ReturnError.unavailableHandoff
        }
        return record
    }
    public func snapshot(handoffID: String) throws -> HandoffPayload {
        try queue.read { HandoffPayload(record: try Self.returnableRecord($0, id: handoffID)) }
    }
    /// Local display only. The MCP interface must use the allowlisted snapshot instead.
    public func recordForDisplay(handoffID: String) throws -> HopRecord? {
        try queue.read { try Self.record($0, id: handoffID) }
    }
    public func insert(_ result: HandoffResult) throws {
        try queue.write { db in
            guard !result.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReturnError.emptyContent }
            guard !result.agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReturnError.emptyAgent }
            _ = try Self.returnableRecord(db, id: result.handoffID)
            try result.insert(db)
        }
    }
    public func results(handoffID: String? = nil, limit: Int = 20) throws -> [HandoffResult] {
        try queue.read { db in
            var request = HandoffResult.all()
            if let handoffID { request = request.filter(sql: "handoff_id = ?", arguments: [handoffID]) }
            return try request.order(sql: "created_at DESC, id DESC").limit(max(1, limit)).fetchAll(db)
        }
    }
    public func result(id: String) throws -> HandoffResult? {
        try queue.read { try HandoffResult.fetchOne($0, key: id) }
    }
    public func count(handoffID: String? = nil) throws -> Int {
        try queue.read { db in
            if let handoffID {
                return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM handoff_results WHERE handoff_id = ?", arguments: [handoffID]) ?? 0
            }
            return try HandoffResult.fetchCount(db)
        }
    }
}
