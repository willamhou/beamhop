import Foundation

// Beamhop deliberately avoids a package dependency for the small SQLite surface
// it needs. The executable is linked to libsqlite3 in Package.swift and these
// declarations mirror SQLite's stable C ABI.
private typealias SQLiteDestructor = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias SQLiteExecCallback = @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
    UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_open_v2")
private func sqlite3_open_v2(
    _ filename: UnsafePointer<CChar>?,
    _ database: UnsafeMutablePointer<OpaquePointer?>?,
    _ flags: Int32,
    _ vfs: UnsafePointer<CChar>?
) -> Int32

@_silgen_name("sqlite3_close_v2")
private func sqlite3_close_v2(_ database: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_errmsg")
private func sqlite3_errmsg(_ database: OpaquePointer?) -> UnsafePointer<CChar>?

@_silgen_name("sqlite3_exec")
private func sqlite3_exec(
    _ database: OpaquePointer?,
    _ sql: UnsafePointer<CChar>?,
    _ callback: SQLiteExecCallback?,
    _ context: UnsafeMutableRawPointer?,
    _ errorMessage: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_free")
private func sqlite3_free(_ pointer: UnsafeMutableRawPointer?)

@_silgen_name("sqlite3_prepare_v2")
private func sqlite3_prepare_v2(
    _ database: OpaquePointer?,
    _ sql: UnsafePointer<CChar>?,
    _ byteCount: Int32,
    _ statement: UnsafeMutablePointer<OpaquePointer?>?,
    _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?
) -> Int32

@_silgen_name("sqlite3_step")
private func sqlite3_step(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_finalize")
private func sqlite3_finalize(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_reset")
private func sqlite3_reset(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_clear_bindings")
private func sqlite3_clear_bindings(_ statement: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_bind_null")
private func sqlite3_bind_null(_ statement: OpaquePointer?, _ index: Int32) -> Int32

@_silgen_name("sqlite3_bind_int64")
private func sqlite3_bind_int64(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64) -> Int32

@_silgen_name("sqlite3_bind_double")
private func sqlite3_bind_double(_ statement: OpaquePointer?, _ index: Int32, _ value: Double) -> Int32

@_silgen_name("sqlite3_bind_text")
private func sqlite3_bind_text(
    _ statement: OpaquePointer?,
    _ index: Int32,
    _ value: UnsafePointer<CChar>?,
    _ byteCount: Int32,
    _ destructor: SQLiteDestructor?
) -> Int32

@_silgen_name("sqlite3_column_type")
private func sqlite3_column_type(_ statement: OpaquePointer?, _ index: Int32) -> Int32

@_silgen_name("sqlite3_column_int64")
private func sqlite3_column_int64(_ statement: OpaquePointer?, _ index: Int32) -> Int64

@_silgen_name("sqlite3_column_double")
private func sqlite3_column_double(_ statement: OpaquePointer?, _ index: Int32) -> Double

@_silgen_name("sqlite3_column_text")
private func sqlite3_column_text(_ statement: OpaquePointer?, _ index: Int32) -> UnsafePointer<UInt8>?

@_silgen_name("sqlite3_last_insert_rowid")
private func sqlite3_last_insert_rowid(_ database: OpaquePointer?) -> Int64

@_silgen_name("sqlite3_changes")
private func sqlite3_changes(_ database: OpaquePointer?) -> Int32

@_silgen_name("sqlite3_busy_timeout")
private func sqlite3_busy_timeout(_ database: OpaquePointer?, _ milliseconds: Int32) -> Int32

private let sqliteOK: Int32 = 0
private let sqliteCorrupt: Int32 = 11
private let sqliteNotADB: Int32 = 26
private let sqliteRow: Int32 = 100
private let sqliteDone: Int32 = 101
private let sqliteNull: Int32 = 5
private let sqliteOpenReadWrite: Int32 = 0x0000_0002
private let sqliteOpenCreate: Int32 = 0x0000_0004
private let sqliteOpenFullMutex: Int32 = 0x0001_0000

public enum BeamhopDatabaseError: Error, CustomStringConvertible, Equatable {
    case sqlite(code: Int32, message: String)
    case integrityCheckFailed(String)
    case schemaIncomplete(missingObjects: [String])
    case captureNotFound(String)
    case invalidCapture(String)

    public var description: String {
        switch self {
        case let .sqlite(code, message):
            return "SQLite error \(code): \(message)"
        case let .integrityCheckFailed(message):
            return "SQLite integrity check failed: \(message)"
        case let .schemaIncomplete(objects):
            return "SQLite schema is incomplete: \(objects.joined(separator: ", "))"
        case let .captureNotFound(id):
            return "Capture not found: \(id)"
        case let .invalidCapture(message):
            return "Invalid capture: \(message)"
        }
    }

    fileprivate var indicatesCorruption: Bool {
        switch self {
        case let .sqlite(code, _):
            return code == sqliteCorrupt || code == sqliteNotADB
        case .integrityCheckFailed:
            return true
        default:
            return false
        }
    }
}

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
}

final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        var opened: OpaquePointer?
        let result = url.path.withCString {
            sqlite3_open_v2(
                $0,
                &opened,
                sqliteOpenReadWrite | sqliteOpenCreate | sqliteOpenFullMutex,
                nil
            )
        }
        handle = opened
        guard result == sqliteOK, opened != nil else {
            let message = opened.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:))
                ?? "Unable to open database"
            if let opened { _ = sqlite3_close_v2(opened) }
            handle = nil
            throw BeamhopDatabaseError.sqlite(code: result, message: message)
        }
        _ = sqlite3_busy_timeout(opened, 5_000)
    }

    deinit {
        if let handle { _ = sqlite3_close_v2(handle) }
    }

    static func openRecovering(at url: URL) throws -> (database: SQLiteDatabase, backupURL: URL?) {
        let fileManager = FileManager.default
        let existed = fileManager.fileExists(atPath: url.path)
        do {
            let database = try SQLiteDatabase(url: url)
            if existed { try database.verifyIntegrity() }
            try database.configureAndMigrate()
            return (database, nil)
        } catch let error as BeamhopDatabaseError where existed && error.indicatesCorruption {
            let backupURL = try moveBrokenDatabase(at: url, fileManager: fileManager)
            let database = try SQLiteDatabase(url: url)
            try database.configureAndMigrate()
            return (database, backupURL)
        }
    }

    private static func moveBrokenDatabase(at url: URL, fileManager: FileManager) throws -> URL {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1_000)
        var backup = URL(fileURLWithPath: "\(url.path).broken.\(timestamp)")
        if fileManager.fileExists(atPath: backup.path) {
            backup = URL(fileURLWithPath: "\(backup.path).\(UUID().uuidString)")
        }
        try fileManager.moveItem(at: url, to: backup)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try? fileManager.moveItem(
                    at: sidecar,
                    to: URL(fileURLWithPath: backup.path + suffix)
                )
            }
        }
        return backup
    }

    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sql.withCString {
            sqlite3_exec(handle, $0, nil, nil, &errorPointer)
        }
        guard result == sqliteOK else {
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
                sqlite3_free(UnsafeMutableRawPointer(errorPointer))
            } else {
                message = errorMessage
            }
            throw BeamhopDatabaseError.sqlite(code: result, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        try SQLiteStatement(database: self, sql: sql)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    func verifyIntegrity() throws {
        let statement: SQLiteStatement
        do {
            statement = try prepare("PRAGMA quick_check")
            guard try statement.step() else {
                throw BeamhopDatabaseError.integrityCheckFailed("quick_check returned no rows")
            }
        } catch let error as BeamhopDatabaseError where error.indicatesCorruption {
            throw error
        } catch {
            throw BeamhopDatabaseError.integrityCheckFailed(String(describing: error))
        }
        let result = statement.text(at: 0) ?? "unknown error"
        guard result == "ok" else {
            throw BeamhopDatabaseError.integrityCheckFailed(result)
        }
    }

    private func configureAndMigrate() throws {
        try execute("PRAGMA foreign_keys = ON; PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        try execute(DatabaseSchema.creationSQL)
        try execute("PRAGMA user_version = \(DatabaseSchema.version)")
        try validateSchema()
    }

    private func validateSchema() throws {
        let required = Set(DatabaseSchema.requiredObjects)
        let statement = try prepare(
            "SELECT name FROM sqlite_master WHERE name IN (\(required.map { _ in "?" }.joined(separator: ",")))"
        )
        for (offset, name) in required.sorted().enumerated() {
            try statement.bind(.text(name), at: Int32(offset + 1))
        }
        var present = Set<String>()
        while try statement.step() {
            if let name = statement.text(at: 0) { present.insert(name) }
        }
        let missing = required.subtracting(present).sorted()
        guard missing.isEmpty else {
            throw BeamhopDatabaseError.schemaIncomplete(missingObjects: missing)
        }
    }

    fileprivate var errorMessage: String {
        sqlite3_errmsg(handle).map(String.init(cString:)) ?? "Unknown SQLite error"
    }
}

final class SQLiteStatement {
    private unowned let database: SQLiteDatabase
    private var handle: OpaquePointer?

    init(database: SQLiteDatabase, sql: String) throws {
        self.database = database
        var prepared: OpaquePointer?
        let result = sql.withCString { sqlite3_prepare_v2(database.handle, $0, -1, &prepared, nil) }
        guard result == sqliteOK, prepared != nil else {
            throw BeamhopDatabaseError.sqlite(code: result, message: database.errorMessage)
        }
        handle = prepared
    }

    deinit {
        if let handle { _ = sqlite3_finalize(handle) }
    }

    func bind(_ value: SQLiteValue, at index: Int32) throws {
        let result: Int32
        switch value {
        case .null:
            result = sqlite3_bind_null(handle, index)
        case let .integer(value):
            result = sqlite3_bind_int64(handle, index, value)
        case let .real(value):
            result = sqlite3_bind_double(handle, index, value)
        case let .text(value):
            let transient = unsafeBitCast(-1, to: SQLiteDestructor?.self)
            let byteCount = Int32(clamping: value.utf8.count)
            result = value.withCString { sqlite3_bind_text(handle, index, $0, byteCount, transient) }
        }
        guard result == sqliteOK else {
            throw BeamhopDatabaseError.sqlite(code: result, message: database.errorMessage)
        }
    }

    /// Returns `true` for a row and `false` once the statement is done.
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case sqliteRow: return true
        case sqliteDone: return false
        default:
            throw BeamhopDatabaseError.sqlite(code: result, message: database.errorMessage)
        }
    }

    func reset() throws {
        let resetResult = sqlite3_reset(handle)
        let clearResult = sqlite3_clear_bindings(handle)
        guard resetResult == sqliteOK, clearResult == sqliteOK else {
            throw BeamhopDatabaseError.sqlite(
                code: resetResult == sqliteOK ? clearResult : resetResult,
                message: database.errorMessage
            )
        }
    }

    func isNull(at index: Int32) -> Bool { sqlite3_column_type(handle, index) == sqliteNull }
    func integer(at index: Int32) -> Int64 { sqlite3_column_int64(handle, index) }
    func real(at index: Int32) -> Double { sqlite3_column_double(handle, index) }

    func text(at index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(handle, index) else { return nil }
        return String(cString: UnsafeRawPointer(pointer).assumingMemoryBound(to: CChar.self))
    }
}

public enum DatabaseSchema {
    public static let version = 1

    public static let requiredObjects = [
        "captures",
        "deliveries",
        "captures_fts",
        "captures_fts_cjk",
        "captures_ai",
        "captures_ad",
        "captures_au"
    ]

    /// Kept public so diagnostics can show the exact durable schema expected by
    /// the running build.
    public static let creationSQL = """
    CREATE TABLE IF NOT EXISTS captures (
        id                  TEXT PRIMARY KEY,
        created_at          INTEGER NOT NULL,
        source              TEXT NOT NULL CHECK(source IN ('browser', 'ax', 'screenshot')),
        app_bundle_id       TEXT NOT NULL,
        app_name            TEXT NOT NULL,
        window_title        TEXT,
        url                 TEXT,
        selected_text       TEXT,
        extracted_body      TEXT,
        domain_hint         TEXT,
        user_note           TEXT,
        screenshot_path     TEXT,
        deleted_at          INTEGER,
        pid                 INTEGER NOT NULL,
        app_version         TEXT,
        os_version          TEXT NOT NULL,
        beamhop_version     TEXT NOT NULL,
        ax_tree_snapshot    TEXT,
        capture_method      TEXT NOT NULL,
        extension_version   TEXT,
        is_private          INTEGER NOT NULL DEFAULT 0 CHECK(is_private IN (0, 1)),
        truncated           INTEGER NOT NULL DEFAULT 0 CHECK(truncated IN (0, 1)),
        capture_duration_ms INTEGER
    );

    CREATE TABLE IF NOT EXISTS deliveries (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        capture_id      TEXT NOT NULL REFERENCES captures(id) ON DELETE CASCADE,
        target          TEXT NOT NULL,
        delivered_at    INTEGER NOT NULL,
        status          TEXT NOT NULL CHECK(status IN ('success', 'failed', 'cancelled')),
        error_message   TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_captures_created ON captures(created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_captures_deleted ON captures(deleted_at);
    CREATE INDEX IF NOT EXISTS idx_deliveries_capture ON deliveries(capture_id, delivered_at DESC);

    CREATE VIRTUAL TABLE IF NOT EXISTS captures_fts USING fts5(
        window_title, url, selected_text, extracted_body, user_note,
        content='captures', content_rowid='rowid',
        tokenize='unicode61 remove_diacritics 2'
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS captures_fts_cjk USING fts5(
        window_title, selected_text, extracted_body, user_note,
        content='captures', content_rowid='rowid',
        tokenize='trigram'
    );

    CREATE TRIGGER IF NOT EXISTS captures_ai AFTER INSERT ON captures
    WHEN new.deleted_at IS NULL BEGIN
        INSERT INTO captures_fts(rowid, window_title, url, selected_text, extracted_body, user_note)
        VALUES (new.rowid, new.window_title, new.url, new.selected_text, new.extracted_body, new.user_note);
        INSERT INTO captures_fts_cjk(rowid, window_title, selected_text, extracted_body, user_note)
        VALUES (new.rowid, new.window_title, new.selected_text, new.extracted_body, new.user_note);
    END;

    CREATE TRIGGER IF NOT EXISTS captures_ad AFTER DELETE ON captures
    WHEN old.deleted_at IS NULL BEGIN
        INSERT INTO captures_fts(captures_fts, rowid, window_title, url, selected_text, extracted_body, user_note)
        VALUES ('delete', old.rowid, old.window_title, old.url, old.selected_text, old.extracted_body, old.user_note);
        INSERT INTO captures_fts_cjk(captures_fts_cjk, rowid, window_title, selected_text, extracted_body, user_note)
        VALUES ('delete', old.rowid, old.window_title, old.selected_text, old.extracted_body, old.user_note);
    END;

    CREATE TRIGGER IF NOT EXISTS captures_au AFTER UPDATE ON captures BEGIN
        INSERT INTO captures_fts(captures_fts, rowid, window_title, url, selected_text, extracted_body, user_note)
        SELECT 'delete', old.rowid, old.window_title, old.url, old.selected_text, old.extracted_body, old.user_note
        WHERE old.deleted_at IS NULL;
        INSERT INTO captures_fts_cjk(captures_fts_cjk, rowid, window_title, selected_text, extracted_body, user_note)
        SELECT 'delete', old.rowid, old.window_title, old.selected_text, old.extracted_body, old.user_note
        WHERE old.deleted_at IS NULL;
        INSERT INTO captures_fts(rowid, window_title, url, selected_text, extracted_body, user_note)
        SELECT new.rowid, new.window_title, new.url, new.selected_text, new.extracted_body, new.user_note
        WHERE new.deleted_at IS NULL;
        INSERT INTO captures_fts_cjk(rowid, window_title, selected_text, extracted_body, user_note)
        SELECT new.rowid, new.window_title, new.selected_text, new.extracted_body, new.user_note
        WHERE new.deleted_at IS NULL;
    END;
    """
}
