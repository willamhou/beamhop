import Foundation
import XCTest
@testable import BeamhopCore

final class CaptureRepositoryTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var repository: CaptureRepository!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BeamhopCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        repository = try CaptureRepository(databaseURL: temporaryDirectory.appendingPathComponent("inbox.sqlite"))
    }

    override func tearDownWithError() throws {
        repository = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testCRUDPreservesCaptureAndProvenance() throws {
        var capture = makeCapture(id: "cap_crud", title: "Fix race condition")
        try repository.insert(capture)

        XCTAssertEqual(try repository.capture(id: capture.id), capture)
        XCTAssertEqual(try repository.latest()?.id, capture.id)
        XCTAssertEqual(try repository.recent(limit: 10).map(\.id), [capture.id])

        capture.windowTitle = "Fix queue deadlock"
        capture.userNote = "Review locking order"
        capture.provenance.isTruncated = true
        try repository.update(capture)
        XCTAssertEqual(try repository.capture(id: capture.id), capture)
    }

    func testUnicodeAndTrigramSearchStayInSyncAcrossUpdateAndSoftDelete() throws {
        var english = makeCapture(
            id: "cap_english",
            title: "Fix race condition in queue",
            createdAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let chinese = makeCapture(
            id: "cap_chinese",
            title: "分析队列竞态条件与锁顺序",
            createdAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        try repository.insert(english)
        try repository.insert(chinese)

        XCTAssertEqual(try repository.search("race").map(\.id), [english.id])
        XCTAssertEqual(try repository.search("竞态条件").map(\.id), [chinese.id])

        english.windowTitle = "Fix semaphore starvation"
        try repository.update(english)
        XCTAssertTrue(try repository.search("race").isEmpty)
        XCTAssertEqual(try repository.search("starvation").map(\.id), [english.id])

        XCTAssertTrue(try repository.softDelete(id: chinese.id, at: Date(timeIntervalSince1970: 1_700_000_003)))
        XCTAssertNil(try repository.capture(id: chinese.id))
        XCTAssertNotNil(try repository.capture(id: chinese.id, includeDeleted: true))
        XCTAssertTrue(try repository.search("竞态条件").isEmpty)

        XCTAssertTrue(try repository.restore(id: chinese.id))
        XCTAssertEqual(try repository.search("竞态条件").map(\.id), [chinese.id])
    }

    func testPurgeOnlyRemovesCapturesOutsideRecoveryWindow() throws {
        var expired = makeCapture(id: "cap_expired", title: "expired")
        expired.deletedAt = Date(timeIntervalSince1970: 100)
        var recoverable = makeCapture(id: "cap_recoverable", title: "recoverable")
        recoverable.deletedAt = Date(timeIntervalSince1970: 300)
        try repository.insert(expired)
        try repository.insert(recoverable)

        XCTAssertEqual(try repository.purgeDeleted(before: Date(timeIntervalSince1970: 200)), 1)
        XCTAssertNil(try repository.capture(id: expired.id, includeDeleted: true))
        XCTAssertNotNil(try repository.capture(id: recoverable.id, includeDeleted: true))
    }

    func testRecordsDeliveryHistoryAndLastSuccessfulTarget() throws {
        let capture = makeCapture(id: "cap_delivery", title: "Delivery")
        try repository.insert(capture)
        let failed = try repository.recordDelivery(Delivery(
            captureID: capture.id,
            target: .chatGPTDesktop,
            deliveredAt: Date(timeIntervalSince1970: 1_700_000_010),
            status: .failed,
            errorMessage: "AX text area not found; clipboard fallback succeeded"
        ))
        let success = try repository.recordDelivery(Delivery(
            captureID: capture.id,
            target: .claudeCode,
            deliveredAt: Date(timeIntervalSince1970: 1_700_000_011),
            status: .success
        ))

        XCTAssertNotNil(failed.id)
        XCTAssertNotNil(success.id)
        XCTAssertEqual(try repository.deliveries(for: capture.id), [success, failed])
        XCTAssertEqual(try repository.lastSuccessfulDeliveryTarget(), .claudeCode)
    }

    func testRejectsDeliveryForMissingCapture() throws {
        XCTAssertThrowsError(try repository.recordDelivery(Delivery(
            captureID: "cap_missing",
            target: .clipboard,
            status: .failed,
            errorMessage: "Nothing to copy"
        ))) { error in
            XCTAssertEqual(error as? BeamhopDatabaseError, .captureNotFound("cap_missing"))
        }
    }

    func testCorruptDatabaseIsPreservedAndRebuilt() throws {
        repository = nil
        let databaseURL = temporaryDirectory.appendingPathComponent("damaged.sqlite")
        let original = Data("this is not a sqlite database".utf8)
        try original.write(to: databaseURL)

        let recovered = try CaptureRepository(databaseURL: databaseURL)
        let backupURL = try XCTUnwrap(recovered.recoveredDatabaseBackupURL)
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))

        let capture = makeCapture(id: "cap_after_recovery", title: "Recovered")
        try recovered.insert(capture)
        XCTAssertEqual(try recovered.latest()?.id, capture.id)
    }

    func testSchemaIncludesDualFTSAndSoftDeleteTriggers() {
        XCTAssertTrue(DatabaseSchema.creationSQL.contains("tokenize='unicode61 remove_diacritics 2'"))
        XCTAssertTrue(DatabaseSchema.creationSQL.contains("tokenize='trigram'"))
        XCTAssertTrue(DatabaseSchema.creationSQL.contains("CREATE TRIGGER IF NOT EXISTS captures_au"))
        XCTAssertTrue(DatabaseSchema.creationSQL.contains("WHERE new.deleted_at IS NULL"))
    }

    private func makeCapture(
        id: String,
        title: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Capture {
        Capture(
            id: id,
            createdAt: createdAt,
            source: .browser,
            appBundleID: "com.google.Chrome",
            appName: "Chrome",
            windowTitle: title,
            url: URL(string: "https://github.com/beamhop/beamhop/pull/1")!,
            selectedText: "if queue.count > 0 { dequeue() }",
            extractedBody: "A detailed review of concurrency and locking order.",
            screenshotPath: "screenshots/2026-08/\(id).png",
            userNote: "Review this change",
            domainHint: "github.pr",
            provenance: CaptureProvenance(
                processID: 42,
                appVersion: "128.0",
                operatingSystemVersion: "15.6",
                beamhopVersion: "0.1.0",
                accessibilityTreeSnapshot: #"{"role":"AXWindow"}"#,
                captureMethod: .browserExtension,
                extensionVersion: "0.1.0",
                isPrivate: false,
                isTruncated: false,
                captureDurationMilliseconds: 37
            )
        )
    }
}
