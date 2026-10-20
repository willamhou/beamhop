import Foundation
import GRDB

/// CRUD + full-text search over captures (spec §8.1).
///
/// Search note: dual FTS recall (unicode61 word-level + trigram CJK substring) → UNION by id →
/// rank by bm25 + time decay. CJK is substring-level (trigram), NOT semantic — Phase 2 adds
/// embeddings. trigram also needs queries of ≥ 3 chars to match.
public final class CaptureStore {
    private let db: Database
    public init(_ db: Database) { self.db = db }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: writes

    public func insert(_ capture: Capture) throws {
        try db.queue.write { try capture.insert($0) }
    }

    public func recordDelivery(_ delivery: Delivery) throws {
        var d = delivery
        try db.queue.write { try d.insert($0) }
    }

    public func setUserNote(_ note: String?, captureID: String) throws {
        try db.queue.write { db in
            try db.execute(sql: "UPDATE captures SET user_note = ? WHERE id = ?",
                           arguments: [note, captureID])
        }
    }

    /// Soft delete (spec §8.1): set deleted_at; the FTS update trigger keeps the index in sync,
    /// and `search`/`recent` both filter `deleted_at IS NULL`.
    public func softDelete(id: String) throws {
        try db.queue.write { db in
            try db.execute(sql: "UPDATE captures SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [nowMs(), id])
        }
    }

    /// Physically remove rows soft-deleted longer than `retentionDays` (spec: 30 days).
    @discardableResult
    public func purgeExpired(retentionDays: Int = 30) throws -> Int {
        let cutoff = nowMs() - Int64(retentionDays) * 24 * 3600 * 1000
        return try db.queue.write { db in
            try db.execute(sql: "DELETE FROM captures WHERE deleted_at IS NOT NULL AND deleted_at < ?",
                           arguments: [cutoff])
            return db.changesCount
        }
    }

    // MARK: reads

    public func fetch(id: String) throws -> Capture? {
        try db.queue.read { try Capture.fetchOne($0, key: id) }
    }

    public func recent(limit: Int = 100) throws -> [Capture] {
        try db.queue.read { db in
            try Capture
                .filter(sql: "deleted_at IS NULL")
                .order(sql: "created_at DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try db.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM captures WHERE deleted_at IS NULL") ?? 0
        }
    }

    /// Delivery history for one capture, newest first (Inbox failure-recovery UI, spec §12.4).
    public func deliveries(captureID: String, limit: Int = 20) throws -> [Delivery] {
        try db.queue.read { db in
            try Delivery
                .filter(sql: "capture_id = ?", arguments: [captureID])
                .order(sql: "delivered_at DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Full-text search across both FTS tables, excluding soft-deleted rows.
    public func search(_ query: String, limit: Int = 50) throws -> [Capture] {
        try db.queue.read { try CaptureSearch.run($0, query: query, limit: limit, nowMs: nowMs()) }
    }

    // MARK: results (agent write-back, memory-mcp-decision spec 2026-10-18)

    public func insertResult(_ result: CaptureResult) throws {
        try db.queue.write { try result.insert($0) }
    }

    /// Write-back conclusions for one capture, newest first.
    public func results(captureID: String, limit: Int = 20) throws -> [CaptureResult] {
        try db.queue.read { db in
            try CaptureResult
                .filter(sql: "origin_capture_id = ?", arguments: [captureID])
                .order(sql: "created_at DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Most recent write-backs across all captures (cross-agent activity view).
    public func recentResults(limit: Int = 50) throws -> [CaptureResult] {
        try db.queue.read { db in
            try CaptureResult.order(sql: "created_at DESC").limit(limit).fetchAll(db)
        }
    }
}
