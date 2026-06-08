import XCTest
import Foundation
@testable import BeamhopCore

final class StorageTests: XCTestCase {
    var tmpDir: URL!
    var dbURL: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beamhop-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        dbURL = tmpDir.appendingPathComponent("inbox.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    private func makeStore() throws -> CaptureStore {
        CaptureStore(try Database(path: dbURL))
    }

    private func sample(
        id: String = ULID.captureID(),
        appName: String = "Safari",
        windowTitle: String? = "Fix race condition in queue",
        selectedText: String? = "if (q.size > 0) { ... }",
        extractedBody: String? = nil
    ) -> Capture {
        Capture(id: id, source: .ax, appBundleID: "com.apple.Safari", appName: appName,
                windowTitle: windowTitle, url: "https://github.com/foo/bar",
                selectedText: selectedText, extractedBody: extractedBody,
                pid: 123, captureMethod: "ax")
    }

    func testInsertAndRecent() throws {
        let store = try makeStore()
        try store.insert(sample())
        let recent = try store.recent()
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.appName, "Safari")
        XCTAssertEqual(try store.count(), 1)
    }

    func testEnglishWordSearch_unicode61() throws {
        let store = try makeStore()
        try store.insert(sample(windowTitle: "Fix race condition", selectedText: "queue overflow bug"))
        XCTAssertEqual(try store.search("queue").count, 1)
        XCTAssertEqual(try store.search("race").count, 1)
        XCTAssertEqual(try store.search("nonexistentword").count, 0)
    }

    func testCJKSubstringSearch_trigram() throws {
        let store = try makeStore()
        // trigram needs >= 3 chars
        try store.insert(sample(windowTitle: "修复队列竞态条件", selectedText: "中文搜索测试内容"))
        XCTAssertEqual(try store.search("搜索测试").count, 1)
        XCTAssertEqual(try store.search("队列竞态").count, 1)
        XCTAssertEqual(try store.search("不存在的词").count, 0)
    }

    func testSoftDeleteExcludedFromRecentAndSearch() throws {
        let store = try makeStore()
        let c = sample(selectedText: "uniquetoken123")
        try store.insert(c)
        XCTAssertEqual(try store.search("uniquetoken123").count, 1)
        try store.softDelete(id: c.id)
        XCTAssertEqual(try store.recent().count, 0)
        // codex review: soft-deleted rows must NOT be returned by FTS search
        XCTAssertEqual(try store.search("uniquetoken123").count, 0)
        XCTAssertEqual(try store.count(), 0)
    }

    func testPurgeExpired() throws {
        let store = try makeStore()
        // a capture soft-deleted 40 days ago
        var old = sample()
        old.deletedAt = Int64(Date().addingTimeInterval(-40 * 86400).timeIntervalSince1970 * 1000)
        try store.insert(old)
        // a capture soft-deleted just now
        let recentDel = sample()
        try store.insert(recentDel)
        try store.softDelete(id: recentDel.id)

        let purged = try store.purgeExpired(retentionDays: 30)
        XCTAssertEqual(purged, 1) // only the 40-day-old one
    }

    func testProvenanceRoundTrips() throws {
        let store = try makeStore()
        var c = sample()
        c.appVersion = "17.5"
        c.captureDurationMs = 42
        c.isPrivate = true
        c.truncated = true
        c.domainHint = .githubPR
        try store.insert(c)
        let fetched = try store.fetch(id: c.id)
        XCTAssertEqual(fetched?.appVersion, "17.5")
        XCTAssertEqual(fetched?.captureDurationMs, 42)
        XCTAssertEqual(fetched?.isPrivate, true)
        XCTAssertEqual(fetched?.truncated, true)
        XCTAssertEqual(fetched?.domainHint, .githubPR)
        XCTAssertEqual(fetched?.osVersion, Version.os)
    }

    func testCorruptionRecovery() throws {
        // create a valid DB + a row
        do {
            let store = try makeStore()
            try store.insert(sample())
        }
        // realistic corruption under WAL: garbage the main file AND drop -wal/-shm (data lives
        // in -wal, so corrupting only the main file would be recoverable, not corruption)
        try Data("not a sqlite database".utf8).write(to: dbURL)
        for s in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: dbURL.path + s) }
        // reopen → should back up the broken file and rebuild empty
        let db = try Database(path: dbURL)
        XCTAssertTrue(db.recoveredFromCorruption)
        let store = CaptureStore(db)
        XCTAssertEqual(try store.count(), 0)
        // a .broken.* backup should exist
        let siblings = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(siblings.contains { $0.contains(".broken.") })
    }

    func testULIDShortPrefix() throws {
        let id = ULID.captureID()
        XCTAssertTrue(id.hasPrefix("cap_"))
        XCTAssertEqual(id.count, 4 + 26)
        XCTAssertEqual(ULID.shortPrefix(of: id).count, 4 + 6)
    }
}
