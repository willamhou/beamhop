import Foundation
import GRDB

/// Dual-FTS5 recall shared by CaptureStore (app process) and CaptureReader (MCP process).
/// Extracted 2026-10-18 so `search_captures` can be exposed over MCP without duplicating logic.
enum CaptureSearch {
    /// Query both FTS tables (unicode61 word-level + trigram CJK substring), UNION by rowid,
    /// rank by bm25 + mild time decay. CJK is substring-level, NOT semantic — Phase 2 adds
    /// embeddings. trigram needs queries of ≥ 3 chars to match.
    static func run(_ db: GRDB.Database, query: String, limit: Int, nowMs: Int64) throws -> [Capture] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        // Treat the whole input as a phrase/substring to avoid FTS5 operator parsing.
        let pattern = "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\""

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

        let now = Double(nowMs)
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
