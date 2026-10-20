import Foundation
import GRDB

/// CRUD for the "先留着" hold stack (product essay 01). The pocket keeps ORDER (position),
/// the note, and the intended target of each held material so an interrupted stack comes
/// back exactly as it was left — "放下再拿起".
public final class PocketStore {
    private let db: Database
    public init(_ db: Database) { self.db = db }

    // MARK: writes

    /// Append at the end of the stack (position = max + 1). Holding preserves the order
    /// materials were gathered in — that order is part of the handoff's meaning.
    @discardableResult
    public func hold(captureID: String, note: String?, intendedTarget: DeliveryTarget?, workName: String? = nil) throws -> PocketItem {
        try db.queue.write { db in
            let maxPos = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), 0) FROM pocket_items")) ?? 0
            var item = PocketItem(captureID: captureID,
                                  note: note?.isEmpty == true ? nil : note,
                                  workName: workName?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  intendedTarget: intendedTarget,
                                  position: maxPos + 1)
            try item.insert(db)
            return item
        }
    }

    /// Remove one item (sent or dismissed). Positions are normalized to stay dense —
    /// the stack order must read continuously to the user.
    public func remove(id: String) throws {
        try remove(ids: [id])
    }

    /// Remove only the acknowledged handoff, atomically. Other selections stay untouched.
    public func remove(ids: [String]) throws {
        try db.queue.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM pocket_items WHERE id = ?", arguments: [id])
            }
            try Self.normalizePositions(db)
        }
    }

    // MARK: reads

    /// The whole stack, oldest-held first (ascending position).
    public func stack() throws -> [PocketItem] {
        try db.queue.read { db in
            try PocketItem.order(sql: "position ASC").fetchAll(db)
        }
    }

    public func count() throws -> Int {
        try db.queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM pocket_items") ?? 0
        }
    }

    /// Items referencing captures that are still live (not soft-deleted) — the UI view.
    /// Unlabeled tuple: @Published erases tuple labels across module boundaries.
    public func liveStack() throws -> [(PocketItem, Capture)] {
        try db.queue.read { db in
            let items = try PocketItem.order(sql: "position ASC").fetchAll(db)
            var out: [(PocketItem, Capture)] = []
            out.reserveCapacity(items.count)
            for item in items {
                if let cap = try Capture.fetchOne(db, key: item.captureID), cap.deletedAt == nil {
                    out.append((item, cap))
                }
            }
            return out
        }
    }

    private static func normalizePositions(_ db: GRDB.Database) throws {
        let items = try PocketItem.order(sql: "position ASC").fetchAll(db)
        for (idx, var item) in items.enumerated() {
            let wanted = idx + 1
            if item.position != wanted {
                item.position = wanted
                try item.update(db)
            }
        }
    }
}
