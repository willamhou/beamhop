import Foundation
import GRDB

public enum DatabaseError: Error, Equatable {
    case fts5Unavailable
    case trigramUnavailable
    case fileNotFound
}

/// Owns the GRDB connection. On open it (1) self-checks FTS5 + trigram support, (2) runs an
/// integrity check and rebuilds-with-backup if corrupted (spec §8.2), (3) runs migrations.
public final class Database {
    public let queue: DatabaseQueue
    /// Set if corruption recovery ran on open (surfaced in Diagnostics).
    public private(set) var recoveredFromCorruption = false

    public init(path: URL) throws {
        // Capability self-check FIRST (codex review): fail clearly, not deep in a migration.
        try Database.ensureFTS5Capabilities(path: path)

        // Integrity check + corruption recovery (spec §8.2).
        var recovered = false
        if FileManager.default.fileExists(atPath: path.path) {
            if try Database.isCorrupted(path: path) {
                try Database.backupCorruptThenRemove(path: path)
                recovered = true
            }
        }

        // Enforce the declared FK (code review P2-1): SQLite defaults PRAGMA foreign_keys OFF,
        // which let purgeExpired orphan deliveries rows. Migration v2 cleans legacy orphans and
        // rebuilds deliveries with ON DELETE CASCADE to match.
        var config = Configuration()
        config.foreignKeysEnabled = true
        self.queue = try DatabaseQueue(path: path.path, configuration: config)
        self.recoveredFromCorruption = recovered

        // Enable WAL so a separate read-only process (BeamhopMCP) can read without blocking
        // writes (Week 2 Task 0.2). Must run OUTSIDE a transaction → writeWithoutTransaction.
        let mode = try queue.writeWithoutTransaction { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode=WAL;")
        }
        if mode?.lowercased() != "wal" {
            FileHandle.standardError.write(Data("[beamhop] WARN journal_mode=\(mode ?? "nil"), expected wal\n".utf8))
        }

        try Migrations.migrator().migrate(queue)
    }

    /// Read-only opener for the MCP server process (Week 2 Task 0.2 / codex review):
    /// NO migration, NO corruption recovery, NO directory/file creation. Throws if the DB
    /// is missing so the caller can return a structured MCP error instead of fabricating a DB.
    public static func openReadOnly(path: URL) throws -> DatabaseQueue {
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DatabaseError.fileNotFound
        }
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: path.path, configuration: config)
    }

    /// In-memory probe that the linked SQLite supports FTS5 and the `trigram` tokenizer.
    static func ensureFTS5Capabilities(path: URL) throws {
        let probe = try DatabaseQueue() // in-memory
        try probe.write { db in
            do {
                try db.execute(sql: "CREATE VIRTUAL TABLE _p USING fts5(x);")
            } catch { throw DatabaseError.fts5Unavailable }
            do {
                try db.execute(sql: "CREATE VIRTUAL TABLE _pt USING fts5(x, tokenize='trigram');")
            } catch { throw DatabaseError.trigramUnavailable }
        }
    }

    static func isCorrupted(path: URL) throws -> Bool {
        do {
            let q = try DatabaseQueue(path: path.path)
            let result = try q.read { db in
                try String.fetchOne(db, sql: "PRAGMA integrity_check;")
            }
            return result != "ok"
        } catch {
            // couldn't even open / read → treat as corrupted
            return true
        }
    }

    static func backupCorruptThenRemove(path: URL) throws {
        let ts = Int(Date().timeIntervalSince1970)
        let broken = path.deletingLastPathComponent()
            .appendingPathComponent(path.lastPathComponent + ".broken.\(ts)")
        try? FileManager.default.moveItem(at: path, to: broken)
        // also clear -wal/-shm if present
        for suffix in ["-wal", "-shm"] {
            let aux = URL(fileURLWithPath: path.path + suffix)
            try? FileManager.default.removeItem(at: aux)
        }
    }
}
