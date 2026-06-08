import Foundation
import GRDB

public enum DatabaseError: Error, Equatable {
    case fts5Unavailable
    case trigramUnavailable
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

        self.queue = try DatabaseQueue(path: path.path)
        self.recoveredFromCorruption = recovered
        try Migrations.migrator().migrate(queue)
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
