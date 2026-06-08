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

    /// Full-text search across both FTS tables, excluding soft-deleted rows.
    public func search(_ query: String, limit: Int = 50) throws -> [Capture] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Treat the whole input as a phrase/substring to avoid FTS5 operator parsing.
        let pattern = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""

        return try db.queue.read { db in
            var best: [Int64: Double] = [:]   // rowid -> best (lowest) bm25
            func collect(table: String) throws {
                let rows = try Row.fetchAll(db, sql:
                    "SELECT rowid AS rid, bm25(\(table)) AS rank FROM \(table) WHERE \(table) MATCH ?",
                    arguments: [pattern])
                for r in rows {
                    let rid: Int64 = r["rid"]
                    let rank: Double = r["rank"]
                    if let cur = best[rid] { best[rid] = min(cur, rank) } else { best[rid] = rank }
                }
            }
            try collect(table: "captures_fts")
            try collect(table: "captures_fts_cjk")
            if best.isEmpty { return [] }

            let rids = Array(best.keys)
            let placeholders = databaseQuestionMarks(count: rids.count)
            let rows = try Row.fetchAll(db, sql:
                "SELECT *, rowid AS _rowid FROM captures WHERE rowid IN (\(placeholders)) AND deleted_at IS NULL",
                arguments: StatementArguments(rids))

            let now = Double(nowMs())
            let scored: [(Capture, Double)] = try rows.map { row in
                let cap = try Capture(row: row)
                let rid: Int64 = row["_rowid"]
                let bm = best[rid] ?? 0
                // bm25: lower = better. Add a mild recency reward so newer wins ties.
                let ageDays = max(0, (now - Double(cap.createdAt)) / 86_400_000)
                let score = bm + ageDays * 0.05
                return (cap, score)
            }
            return scored.sorted { $0.1 < $1.1 }.prefix(limit).map { $0.0 }
        }
    }
}
