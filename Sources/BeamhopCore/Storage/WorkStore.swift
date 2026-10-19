import Foundation
import GRDB

/// CRUD for named destinations (product essay 02). Invariants:
/// - `name` is unique case-insensitively (NOCASE UNIQUE in v6) — the same work recalled
///   later must resolve to the same row regardless of typing case.
/// - Rebinding (changing `boundTarget`) NEVER touches `confirmedTarget` — the row then
///   reports `needsConfirmation` until `confirm()` is called by an explicit user act.
/// - Only explicit user confirmation (confirm / register) sets `confirmedTarget`.
public final class WorkStore {
    private let db: Database
    public init(_ db: Database) { self.db = db }

    /// Register a new named destination. The registering act itself is the first
    /// confirmation (the user is standing in the receiving session — essay 02's
    /// "登记这个去处的好时机").
    @discardableResult
    public func register(name: String, boundTo target: DeliveryTarget) throws -> Work {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty, "Work name must not be empty")
        return try db.queue.write { db in
            var work = Work(name: trimmed, boundTarget: target, confirmedTarget: target)
            try work.insert(db)
            return work
        }
    }

    /// Rebind an existing work to a new receiver (session ended / tool changed). The new
    /// address is UNCONFIRMED by definition — the next delivery to this work must make the
    /// user verify it (CapturePanelModel's two-step confirm).
    @discardableResult
    public func rebind(id: String, to target: DeliveryTarget) throws -> Work? {
        try db.queue.write { db in
            guard var work = try Work.fetchOne(db, key: id) else { return nil }
            guard work.boundTarget != target else { return work }
            work.boundTarget = target
            work.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try work.update(db)
            return work
        }
    }

    /// The ONLY way confirmedTarget moves. Called solely from explicit user confirmation
    /// in the delivery flow.
    public func confirm(id: String) throws {
        try db.queue.write { db in
            guard var work = try Work.fetchOne(db, key: id) else { return }
            work.confirmedTarget = work.boundTarget
            work.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
            try work.update(db)
        }
    }

    // MARK: reads

    public func fetch(name: String) throws -> Work? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.queue.read { db in
            try Work.filter(sql: "name = ?", arguments: [trimmed]).fetchOne(db)
        }
    }

    public func fetch(id: String) throws -> Work? {
        try db.queue.read { try Work.fetchOne($0, key: id) }
    }

    public func list() throws -> [Work] {
        try db.queue.read { db in
            try Work.order(sql: "updated_at DESC").fetchAll(db)
        }
    }
}
