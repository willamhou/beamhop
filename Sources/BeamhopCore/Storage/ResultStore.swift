import Foundation
import GRDB

/// Read-write access to agent write-backs (the `results` table) for the MCP server process.
///
/// Unlike the app-side `Database`, this opener runs NO migration, NO corruption recovery, and
/// NO directory creation: the Inbox is owned by the Beamhop app, and the MCP process must not
/// run migrations against a live DB. If the `results` table is absent (app not restarted since
/// v3), open fails with `DatabaseError.schemaOutdated` → structured MCP error telling the
/// agent to restart the app.
public final class ResultStore {
    private let queue: DatabaseQueue
    public init(_ queue: DatabaseQueue) { self.queue = queue }

    /// Open read-write from a DB path. Throws `fileNotFound` if the DB doesn't exist,
    /// `schemaOutdated` if migration v3 hasn't run yet.
    public static func open(path: URL) throws -> ResultStore {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DatabaseError.fileNotFound
        }
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(path: path.path, configuration: config)
        let store = ResultStore(queue)
        guard try queue.read({ db in
            try Int.fetchOne(db, sql:
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='results'") ?? 0
        }) > 0 else {
            throw DatabaseError.schemaOutdated
        }
        return store
    }

    // MARK: writes

    /// Insert a write-back. FK rejects origins that don't exist (structured error surfaces it).
    public func insert(_ result: CaptureResult) throws {
        try queue.write { try result.insert($0) }
    }

    // MARK: reads

    public func results(captureID: String, limit: Int = 20) throws -> [CaptureResult] {
        try queue.read { db in
            try CaptureResult
                .filter(sql: "origin_capture_id = ?", arguments: [captureID])
                .order(sql: "created_at DESC")
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func recentResults(limit: Int = 50) throws -> [CaptureResult] {
        try queue.read { db in
            try CaptureResult.order(sql: "created_at DESC").limit(limit).fetchAll(db)
        }
    }
}
