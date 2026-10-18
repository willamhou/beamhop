import Foundation
import GRDB

/// Read-only capture access for the MCP server process (works on a read-only DatabaseQueue).
public final class CaptureReader {
    private let queue: DatabaseQueue
    public init(_ queue: DatabaseQueue) { self.queue = queue }

    /// Open read-only from a DB path (throws DatabaseError.fileNotFound if missing).
    public static func open(path: URL) throws -> CaptureReader {
        CaptureReader(try Database.openReadOnly(path: path))
    }

    public func latest() throws -> Capture? {
        try queue.read { db in
            try Capture.filter(sql: "deleted_at IS NULL").order(sql: "created_at DESC").fetchOne(db)
        }
    }

    public func fetch(id: String) throws -> Capture? {
        try queue.read { db in
            try Capture.filter(sql: "id = ? AND deleted_at IS NULL", arguments: [id]).fetchOne(db)
        }
    }

    /// Full-text search over both FTS tables (same recall as the app-side CaptureStore),
    /// exposed to agents as `search_captures`.
    public func search(_ query: String, limit: Int = 50) throws -> [Capture] {
        try queue.read {
            try CaptureSearch.run($0, query: query, limit: limit,
                                  nowMs: Int64(Date().timeIntervalSince1970 * 1000))
        }
    }

    /// One hit of a deduplicated search: the newest capture of a content-identity group,
    /// plus how many live captures that group has and its time span.
    public struct DeduplicatedHit: Encodable {
        public let capture: Capture
        public let duplicateCount: Int
        public let firstSeenAt: Int64
        public let lastSeenAt: Int64
        enum CodingKeys: String, CodingKey {
            case capture
            case duplicateCount = "duplicate_count"
            case firstSeenAt = "first_seen_at"
            case lastSeenAt = "last_seen_at"
        }
    }

    /// Search with re-capture collapsing (2026-10-18, Claude's Inbox-noise report: the same
    /// page was captured 10+ times, wrecking search SNR for agents). The duplicate-press gate
    /// only covers <500ms; these are minutes-to-hours apart with byte-identical content, so the
    /// fix belongs on the retrieval side: group hits by `contentIdentity`, keep the newest of
    /// each group (in original rank order), and report group stats from the whole live table —
    /// a group may contain captures the query text didn't hit, and they still count.
    public func searchDeduplicated(_ query: String, limit: Int = 10) throws -> [DeduplicatedHit] {
        try queue.read { db in
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            // Over-fetch: collapsing may discard several hits per group.
            let hits = try CaptureSearch.run(db, query: query, limit: max(limit * 5, 25), nowMs: now)

            var order: [String] = []                 // identity, in first-appearance (rank) order
            var groups: [String: [Capture]] = [:]
            for h in hits {
                if groups[h.contentIdentity] == nil { order.append(h.contentIdentity) }
                groups[h.contentIdentity, default: []].append(h)
            }

            var out: [DeduplicatedHit] = []
            for identity in order {
                let reps = groups[identity]!
                // Newest wins; same-ms ties keep the better-ranked (stable sort keeps hit order).
                let rep = reps.sorted { $0.createdAt < $1.createdAt }.last!
                let stats = try Row.fetchOne(db, sql: """
                    SELECT COUNT(*) AS n, MIN(created_at) AS first, MAX(created_at) AS last
                    FROM captures
                    WHERE deleted_at IS NULL
                      AND app_bundle_id = ? AND window_title IS ? AND url IS ?
                      AND selected_text IS ? AND extracted_body IS ?
                    """, arguments: [rep.appBundleID, rep.windowTitle, rep.url,
                                     rep.selectedText, rep.extractedBody])!
                out.append(DeduplicatedHit(capture: rep,
                                           duplicateCount: stats["n"] as Int,
                                           firstSeenAt: stats["first"] as Int64,
                                           lastSeenAt: stats["last"] as Int64))
            }
            return Array(out.prefix(limit))
        }
    }

    /// Encode any record as pretty JSON for an agent to consume.
    public static func renderJSON<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(value), let s = String(data: data, encoding: .utf8) else {
            return "{\"error\":\"encode failed\"}"
        }
        return s
    }
}
