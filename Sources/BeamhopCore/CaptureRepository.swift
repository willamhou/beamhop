import Foundation

public final class CaptureRepository {
    public let databaseURL: URL
    /// Set when startup found a damaged database and preserved it before
    /// creating a clean schema. Screenshot files are intentionally untouched.
    public let recoveredDatabaseBackupURL: URL?

    private let database: SQLiteDatabase
    private let lock = NSRecursiveLock()

    public static func defaultDatabaseURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw BeamhopDatabaseError.invalidCapture("Application Support directory is unavailable")
        }
        return applicationSupport
            .appendingPathComponent("beamhop", isDirectory: true)
            .appendingPathComponent("inbox.sqlite", isDirectory: false)
    }

    public convenience init(fileManager: FileManager = .default) throws {
        try self.init(databaseURL: Self.defaultDatabaseURL(fileManager: fileManager), fileManager: fileManager)
    }

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        let parent = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        let opened = try SQLiteDatabase.openRecovering(at: databaseURL)
        self.databaseURL = databaseURL
        database = opened.database
        recoveredDatabaseBackupURL = opened.backupURL
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: databaseURL.path)
    }

    public func create(_ capture: Capture) throws {
        try synchronized {
            try validate(capture)
            let statement = try database.prepare("""
                INSERT INTO captures (
                    id, created_at, source, app_bundle_id, app_name, window_title, url,
                    selected_text, extracted_body, domain_hint, user_note, screenshot_path,
                    deleted_at, pid, app_version, os_version, beamhop_version,
                    ax_tree_snapshot, capture_method, extension_version, is_private,
                    truncated, capture_duration_ms
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                """)
            try bind(capture, to: statement)
            _ = try statement.step()
        }
    }

    /// Vocabulary alias used by capture pipelines.
    public func insert(_ capture: Capture) throws {
        try create(capture)
    }

    public func update(_ capture: Capture) throws {
        try synchronized {
            try validate(capture)
            let statement = try database.prepare("""
                UPDATE captures SET
                    created_at=?, source=?, app_bundle_id=?, app_name=?, window_title=?, url=?,
                    selected_text=?, extracted_body=?, domain_hint=?, user_note=?, screenshot_path=?,
                    deleted_at=?, pid=?, app_version=?, os_version=?, beamhop_version=?,
                    ax_tree_snapshot=?, capture_method=?, extension_version=?, is_private=?,
                    truncated=?, capture_duration_ms=?
                WHERE id=?
                """)
            try bind(capture.createdAt, to: statement, at: 1)
            try statement.bind(.text(capture.source.rawValue), at: 2)
            try statement.bind(.text(capture.appBundleID), at: 3)
            try statement.bind(.text(capture.appName), at: 4)
            try bind(capture.windowTitle, to: statement, at: 5)
            try bind(capture.url?.absoluteString, to: statement, at: 6)
            try bind(capture.selectedText, to: statement, at: 7)
            try bind(capture.extractedBody, to: statement, at: 8)
            try bind(capture.domainHint, to: statement, at: 9)
            try bind(capture.userNote, to: statement, at: 10)
            try bind(capture.screenshotPath, to: statement, at: 11)
            try bind(capture.deletedAt, to: statement, at: 12)
            try statement.bind(.integer(Int64(capture.provenance.processID)), at: 13)
            try bind(capture.provenance.appVersion, to: statement, at: 14)
            try statement.bind(.text(capture.provenance.operatingSystemVersion), at: 15)
            try statement.bind(.text(capture.provenance.beamhopVersion), at: 16)
            try bind(capture.provenance.accessibilityTreeSnapshot, to: statement, at: 17)
            try statement.bind(.text(capture.provenance.captureMethod.rawValue), at: 18)
            try bind(capture.provenance.extensionVersion, to: statement, at: 19)
            try statement.bind(.integer(capture.provenance.isPrivate ? 1 : 0), at: 20)
            try statement.bind(.integer(capture.provenance.isTruncated ? 1 : 0), at: 21)
            try bind(capture.provenance.captureDurationMilliseconds, to: statement, at: 22)
            try statement.bind(.text(capture.id), at: 23)
            _ = try statement.step()
            guard database.changes == 1 else {
                throw BeamhopDatabaseError.captureNotFound(capture.id)
            }
        }
    }

    public func capture(id: String, includeDeleted: Bool = false) throws -> Capture? {
        try synchronized {
            let predicate = includeDeleted ? "id = ?" : "id = ? AND deleted_at IS NULL"
            let statement = try database.prepare("SELECT \(Self.captureColumns) FROM captures WHERE \(predicate)")
            try statement.bind(.text(id), at: 1)
            return try statement.step() ? try decodeCapture(from: statement) : nil
        }
    }

    public func latest(includeDeleted: Bool = false) throws -> Capture? {
        try synchronized {
            let predicate = includeDeleted ? "1 = 1" : "deleted_at IS NULL"
            let statement = try database.prepare("""
                SELECT \(Self.captureColumns) FROM captures
                WHERE \(predicate) ORDER BY created_at DESC, rowid DESC LIMIT 1
                """)
            return try statement.step() ? try decodeCapture(from: statement) : nil
        }
    }

    public func list(limit: Int = 100, offset: Int = 0, includeDeleted: Bool = false) throws -> [Capture] {
        try synchronized {
            let predicate = includeDeleted ? "1 = 1" : "deleted_at IS NULL"
            let statement = try database.prepare("""
                SELECT \(Self.captureColumns) FROM captures
                WHERE \(predicate)
                ORDER BY created_at DESC, rowid DESC LIMIT ? OFFSET ?
                """)
            try statement.bind(.integer(Int64(max(0, limit))), at: 1)
            try statement.bind(.integer(Int64(max(0, offset))), at: 2)
            return try collectCaptures(from: statement)
        }
    }

    public func recent(limit: Int = 100) throws -> [Capture] {
        try list(limit: limit)
    }

    public func softDelete(id: String, at date: Date = Date()) throws -> Bool {
        try synchronized {
            let statement = try database.prepare(
                "UPDATE captures SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL"
            )
            try bind(date, to: statement, at: 1)
            try statement.bind(.text(id), at: 2)
            _ = try statement.step()
            return database.changes == 1
        }
    }

    public func restore(id: String) throws -> Bool {
        try synchronized {
            let statement = try database.prepare(
                "UPDATE captures SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL"
            )
            try statement.bind(.text(id), at: 1)
            _ = try statement.step()
            return database.changes == 1
        }
    }

    /// Permanently removes captures whose 30-day recovery window has elapsed.
    /// Cascading delivery rows are removed by SQLite; screenshot lifecycle is
    /// intentionally managed by the app so this method never deletes files.
    @discardableResult
    public func purgeDeleted(before cutoff: Date) throws -> Int {
        try synchronized {
            let statement = try database.prepare(
                "DELETE FROM captures WHERE deleted_at IS NOT NULL AND deleted_at < ?"
            )
            try bind(cutoff, to: statement, at: 1)
            _ = try statement.step()
            return database.changes
        }
    }

    public func search(_ query: String, limit: Int = 50) throws -> [Capture] {
        try searchResults(query, limit: limit).map(\.capture)
    }

    public func searchResults(_ query: String, limit: Int = 50, now: Date = Date()) throws -> [CaptureSearchResult] {
        try synchronized {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, limit > 0 else { return [] }

            // Quoting makes arbitrary user punctuation safe for FTS5 MATCH and
            // asks trigram to perform literal substring matching.
            let phrase = "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
            let candidateLimit = max(limit * 8, 100)
            let statement = try database.prepare("""
                WITH ranked AS (
                    SELECT rowid AS capture_rowid, bm25(captures_fts) AS rank
                    FROM captures_fts WHERE captures_fts MATCH ?
                    UNION ALL
                    SELECT rowid AS capture_rowid, bm25(captures_fts_cjk) AS rank
                    FROM captures_fts_cjk WHERE captures_fts_cjk MATCH ?
                ), combined AS (
                    SELECT capture_rowid, MIN(rank) AS best_rank
                    FROM ranked GROUP BY capture_rowid
                )
                SELECT \(Self.captureColumns), combined.best_rank
                FROM combined JOIN captures ON captures.rowid = combined.capture_rowid
                WHERE captures.deleted_at IS NULL
                ORDER BY combined.best_rank ASC, captures.created_at DESC
                LIMIT ?
                """)
            try statement.bind(.text(phrase), at: 1)
            try statement.bind(.text(phrase), at: 2)
            try statement.bind(.integer(Int64(candidateLimit)), at: 3)

            var results: [CaptureSearchResult] = []
            while try statement.step() {
                let capture = try decodeCapture(from: statement)
                let bm25 = statement.real(at: 23)
                let ageDays = max(0, now.timeIntervalSince(capture.createdAt) / 86_400)
                let score = bm25 + min(ageDays, 365) * 0.000_001
                results.append(CaptureSearchResult(capture: capture, score: score))
            }
            return Array(results.sorted {
                if $0.score == $1.score { return $0.capture.createdAt > $1.capture.createdAt }
                return $0.score < $1.score
            }.prefix(limit))
        }
    }

    @discardableResult
    public func recordDelivery(_ delivery: Delivery) throws -> Delivery {
        try synchronized {
            guard try capture(id: delivery.captureID, includeDeleted: true) != nil else {
                throw BeamhopDatabaseError.captureNotFound(delivery.captureID)
            }
            if delivery.status == .failed,
               delivery.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw BeamhopDatabaseError.invalidCapture(
                    "Failed deliveries must include a readable error message"
                )
            }
            let statement = try database.prepare("""
                INSERT INTO deliveries(capture_id, target, delivered_at, status, error_message)
                VALUES (?, ?, ?, ?, ?)
                """)
            try statement.bind(.text(delivery.captureID), at: 1)
            try statement.bind(.text(delivery.target.rawValue), at: 2)
            try bind(delivery.deliveredAt, to: statement, at: 3)
            try statement.bind(.text(delivery.status.rawValue), at: 4)
            try bind(delivery.errorMessage, to: statement, at: 5)
            _ = try statement.step()
            var persisted = delivery
            persisted.id = database.lastInsertRowID
            return persisted
        }
    }

    public func deliveries(for captureID: String) throws -> [Delivery] {
        try synchronized {
            let statement = try database.prepare("""
                SELECT id, capture_id, target, delivered_at, status, error_message
                FROM deliveries WHERE capture_id = ? ORDER BY delivered_at DESC, id DESC
                """)
            try statement.bind(.text(captureID), at: 1)
            var deliveries: [Delivery] = []
            while try statement.step() {
                guard
                    let targetValue = statement.text(at: 2),
                    let target = DeliveryTarget(rawValue: targetValue),
                    let statusValue = statement.text(at: 4),
                    let status = DeliveryStatus(rawValue: statusValue)
                else {
                    throw BeamhopDatabaseError.invalidCapture("Delivery contains an unknown enum value")
                }
                deliveries.append(Delivery(
                    id: statement.integer(at: 0),
                    captureID: statement.text(at: 1) ?? captureID,
                    target: target,
                    deliveredAt: Self.date(fromMilliseconds: statement.integer(at: 3)),
                    status: status,
                    errorMessage: statement.text(at: 5)
                ))
            }
            return deliveries
        }
    }

    public func lastSuccessfulDeliveryTarget() throws -> DeliveryTarget? {
        try synchronized {
            let statement = try database.prepare("""
                SELECT target FROM deliveries WHERE status = 'success'
                ORDER BY delivered_at DESC, id DESC LIMIT 1
                """)
            guard try statement.step(), let value = statement.text(at: 0) else { return nil }
            return DeliveryTarget(rawValue: value)
        }
    }

    private static let captureColumns = """
        captures.id, captures.created_at, captures.source, captures.app_bundle_id,
        captures.app_name, captures.window_title, captures.url, captures.selected_text,
        captures.extracted_body, captures.domain_hint, captures.user_note,
        captures.screenshot_path, captures.deleted_at, captures.pid, captures.app_version,
        captures.os_version, captures.beamhop_version, captures.ax_tree_snapshot,
        captures.capture_method, captures.extension_version, captures.is_private,
        captures.truncated, captures.capture_duration_ms
        """

    private func validate(_ capture: Capture) throws {
        guard !capture.id.isEmpty else { throw BeamhopDatabaseError.invalidCapture("id is empty") }
        guard !capture.appBundleID.isEmpty else {
            throw BeamhopDatabaseError.invalidCapture("appBundleID is empty")
        }
        guard !capture.appName.isEmpty else {
            throw BeamhopDatabaseError.invalidCapture("appName is empty")
        }
        guard !capture.provenance.operatingSystemVersion.isEmpty else {
            throw BeamhopDatabaseError.invalidCapture("operatingSystemVersion is empty")
        }
        guard !capture.provenance.beamhopVersion.isEmpty else {
            throw BeamhopDatabaseError.invalidCapture("beamhopVersion is empty")
        }
    }

    private func bind(_ capture: Capture, to statement: SQLiteStatement) throws {
        try statement.bind(.text(capture.id), at: 1)
        try bind(capture.createdAt, to: statement, at: 2)
        try statement.bind(.text(capture.source.rawValue), at: 3)
        try statement.bind(.text(capture.appBundleID), at: 4)
        try statement.bind(.text(capture.appName), at: 5)
        try bind(capture.windowTitle, to: statement, at: 6)
        try bind(capture.url?.absoluteString, to: statement, at: 7)
        try bind(capture.selectedText, to: statement, at: 8)
        try bind(capture.extractedBody, to: statement, at: 9)
        try bind(capture.domainHint, to: statement, at: 10)
        try bind(capture.userNote, to: statement, at: 11)
        try bind(capture.screenshotPath, to: statement, at: 12)
        try bind(capture.deletedAt, to: statement, at: 13)
        try statement.bind(.integer(Int64(capture.provenance.processID)), at: 14)
        try bind(capture.provenance.appVersion, to: statement, at: 15)
        try statement.bind(.text(capture.provenance.operatingSystemVersion), at: 16)
        try statement.bind(.text(capture.provenance.beamhopVersion), at: 17)
        try bind(capture.provenance.accessibilityTreeSnapshot, to: statement, at: 18)
        try statement.bind(.text(capture.provenance.captureMethod.rawValue), at: 19)
        try bind(capture.provenance.extensionVersion, to: statement, at: 20)
        try statement.bind(.integer(capture.provenance.isPrivate ? 1 : 0), at: 21)
        try statement.bind(.integer(capture.provenance.isTruncated ? 1 : 0), at: 22)
        try bind(capture.provenance.captureDurationMilliseconds, to: statement, at: 23)
    }

    private func decodeCapture(from statement: SQLiteStatement) throws -> Capture {
        guard
            let id = statement.text(at: 0),
            let sourceValue = statement.text(at: 2),
            let source = CaptureSource(rawValue: sourceValue),
            let appBundleID = statement.text(at: 3),
            let appName = statement.text(at: 4),
            let operatingSystemVersion = statement.text(at: 15),
            let beamhopVersion = statement.text(at: 16),
            let methodValue = statement.text(at: 18),
            let method = CaptureMethod(rawValue: methodValue)
        else {
            throw BeamhopDatabaseError.invalidCapture("Database row has missing or unknown required values")
        }

        let url = statement.text(at: 6).flatMap(URL.init(string:))
        let deletedAt = statement.isNull(at: 12)
            ? nil
            : Self.date(fromMilliseconds: statement.integer(at: 12))
        let duration = statement.isNull(at: 22) ? nil : Int(statement.integer(at: 22))

        return Capture(
            id: id,
            createdAt: Self.date(fromMilliseconds: statement.integer(at: 1)),
            source: source,
            appBundleID: appBundleID,
            appName: appName,
            windowTitle: statement.text(at: 5),
            url: url,
            selectedText: statement.text(at: 7),
            extractedBody: statement.text(at: 8),
            screenshotPath: statement.text(at: 11),
            userNote: statement.text(at: 10),
            domainHint: statement.text(at: 9),
            provenance: CaptureProvenance(
                processID: Int(statement.integer(at: 13)),
                appVersion: statement.text(at: 14),
                operatingSystemVersion: operatingSystemVersion,
                beamhopVersion: beamhopVersion,
                accessibilityTreeSnapshot: statement.text(at: 17),
                captureMethod: method,
                extensionVersion: statement.text(at: 19),
                isPrivate: statement.integer(at: 20) != 0,
                isTruncated: statement.integer(at: 21) != 0,
                captureDurationMilliseconds: duration
            ),
            deletedAt: deletedAt
        )
    }

    private func collectCaptures(from statement: SQLiteStatement) throws -> [Capture] {
        var captures: [Capture] = []
        while try statement.step() { captures.append(try decodeCapture(from: statement)) }
        return captures
    }

    private func bind(_ value: String?, to statement: SQLiteStatement, at index: Int32) throws {
        try statement.bind(value.map(SQLiteValue.text) ?? .null, at: index)
    }

    private func bind(_ value: Int?, to statement: SQLiteStatement, at index: Int32) throws {
        try statement.bind(value.map { .integer(Int64($0)) } ?? .null, at: index)
    }

    private func bind(_ value: Date?, to statement: SQLiteStatement, at index: Int32) throws {
        try statement.bind(value.map { .integer(Self.milliseconds(from: $0)) } ?? .null, at: index)
    }

    private static func milliseconds(from date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(fromMilliseconds value: Int64) -> Date {
        Date(timeIntervalSince1970: Double(value) / 1_000)
    }

    private func synchronized<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}
