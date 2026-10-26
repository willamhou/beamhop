import Foundation
import GRDB

/// Append-only local event log for dogfood metrics (evolution-decisions §3 gate). Local-only:
/// never leaves the machine, pruned after `retentionDays`. Event names are FIXED strings —
/// `DogfoodReport` and any ad-hoc sqlite queries match on them, so rename with care.
///
/// Recording is fire-and-forget by design: metrics must never break the capture/delivery path.
public final class EventStore {
    /// Canonical event names (queried by DogfoodReport).
    public enum Name {
        public static let hopActivity = "hop_activity_v1"
        public static let captureCompleted = "capture_completed"
        public static let captureDuplicate = "capture_duplicate"
        public static let captureRejected = "capture_rejected"
        public static let panelShown = "panel_shown"
        public static let panelConfirm = "panel_confirm"
        public static let panelCancel = "panel_cancel"
        public static let inboxOpened = "inbox_opened"
        public static let inboxSearch = "inbox_search"
        public static let captureViewed = "capture_viewed"
        public static let captureSoftDeleted = "capture_soft_deleted"
        public static let inboxRedeliver = "inbox_redeliver"
        // 「先留着」pocket events (2026-10-19 product essays)
        public static let pocketHold = "pocket_hold"
        public static let pocketBatch = "pocket_batch"
        public static let pocketItemDelivered = "pocket_item_delivered"
        public static let pocketItemFailed = "pocket_item_failed"
    }

    struct Row: Codable, FetchableRecord, MutablePersistableRecord {
        static let databaseTableName = "events"
        var id: String
        var ts: Int64
        var name: String
        var detail: String?
        var captureId: String?
        enum CodingKeys: String, CodingKey {
            case id, ts, name, detail
            case captureId = "capture_id"
        }
    }

    private let db: Database
    public init(_ db: Database) { self.db = db }

    /// Append one event. `detail` is a compact `key=value` string (e.g. "ms=42", "target=kimi_work").
    public func record(name: String, detail: String? = nil, captureID: String? = nil, date: Date = Date()) {
        var row = Row(
            id: "evt_" + ULID.generate(date: date),
            ts: Int64(date.timeIntervalSince1970 * 1000),
            name: name,
            detail: detail,
            captureId: captureID)
        try? db.queue.write { try row.insert($0) }
    }

    /// Physically remove events older than `retentionDays` (default: generous vs the 2–4 week
    /// dogfood window; called once at bootstrap).
    @discardableResult
    public func prune(retentionDays: Int = 180) throws -> Int {
        let cutoff = Int64(Date().timeIntervalSince1970 * 1000) - Int64(retentionDays) * 24 * 3600 * 1000
        return try db.queue.write { db in
            try db.execute(sql: "DELETE FROM events WHERE ts < ?", arguments: [cutoff])
            return db.changesCount
        }
    }

    public func count() throws -> Int {
        try db.queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM events") ?? 0 }
    }
}
