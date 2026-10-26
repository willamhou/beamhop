import XCTest

@testable import BeamhopCore

final class TrialWorkflowTests: XCTestCase {
    func testTelemetryCoverageAndNonBlockingFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try Database(path: directory.appendingPathComponent("fixture.sqlite"))
        let draft = HopDraft(materials: [HopMaterial(text: "private material")], route: .init(target: .clipboard))
        let old = HopRecord(draft: draft, status: .copied)
        // Fixture from before telemetry: a real retained backup without a start event.
        try db.queue.write { connection in
            try connection.execute(
                sql: "INSERT INTO hop_records(id,payload) VALUES (?,?)",
                arguments: [old.id, try JSONEncoder().encode(old)])
        }
        var report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(
            report.hops.attempts == 0 && report.hops.untrackedBackups == 1,
            "legacy history is marked untracked, never fabricated into the window")
        try db.queue.write { connection in
            try connection.execute(
                sql:
                    "CREATE TRIGGER reject_usage BEFORE INSERT ON events BEGIN SELECT RAISE(FAIL, 'fixture metrics unavailable'); END"
            )
        }
        let library = try HopLibrary(db)
        try library.start(draft)
        let record = try library.begin(draft)
        try library.finish(record.id, status: .copied)
        let reopened = try HopLibrary(db)
        XCTAssertTrue(
            reopened.state.active == nil && reopened.state.records.last?.status == .copied,
            "telemetry failure never blocks a durable handoff")
        report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(
            report.hops.attempts == 0 && report.hops.untrackedBackups == 2,
            "missing telemetry remains explicit instead of a false success rate")
    }
    func testGuideObservesLibraryAndHandlesPendingRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "beamhop-onboarding-integration-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw NSError(domain: "TrialFixture", code: 1) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)
        let library = try HopLibrary(Database(path: directory.appendingPathComponent("fixture.sqlite")))
        library.onActivity = { model.observe($0) }
        model.captureSaved()
        let record = try library.begin(
            HopDraft(materials: [HopMaterial(text: "private input")], route: .init(target: .clipboard)))
        XCTAssertTrue(model.progress.lastReceipt == .preparing, "guide follows the actual persisted handoff start")
        let reopened = OnboardingModel(defaults: defaults)
        XCTAssertTrue(
            reopened.progress.needsRecovery && !reopened.progress.hasTransportReceipt,
            "restart with pending preparation is unknown, not completion")
        try library.finish(record.id, status: .failed)
        XCTAssertTrue(model.progress.needsRecovery, "actual transport failure opens recovery guidance")
        try library.recover(record)
        XCTAssertTrue(!model.progress.needsRecovery, "actual backup restoration is observed by the guide")
        guard let active = library.state.active else { throw NSError(domain: "TrialFixture", code: 2) }
        let retry = try library.begin(active)
        try library.finish(retry.id, status: .copied)
        XCTAssertTrue(
            model.progress.hasTransportReceipt && model.progress.lastHandoffID == retry.id,
            "actual copy receipt advances manual submission guidance")
    }
    func testReportWindowAndReadOnlyOpening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("fixture.sqlite")
        let db = try Database(path: path)
        let events = EventStore(db)
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        events.recordHop(HopActivity(.started, id: "old"), date: now.addingTimeInterval(-30 * 86400))
        events.recordHop(HopActivity(.copied, id: "old"), date: now)
        events.recordHop(HopActivity(.started, id: "current"), date: now)
        events.recordHop(HopActivity(.prepared, id: "current"), date: now)
        events.recordHop(HopActivity(.started, id: "future"), date: now.addingTimeInterval(10))
        events.record(name: EventStore.Name.captureCompleted, date: now.addingTimeInterval(10))
        let report = try DogfoodReport.generate(db: db, days: 7, now: now)
        XCTAssertTrue(
            report.hops.attempts == 1 && report.hops.prepared == 1 && report.hops.pending == 0,
            "time window excludes old/future starts and handles equal timestamps")
        XCTAssertTrue(report.pressCount == 0, "future capture events are not evidence in this reporting window")
        let missing = directory.appendingPathComponent("missing.sqlite")
        do {
            _ = try DogfoodReport.generate(path: missing)
            XCTAssertTrue(false, "report must reject a missing Inbox")
        } catch {}
        XCTAssertTrue(!FileManager.default.fileExists(atPath: missing.path), "reporting never creates an Inbox")
        do {
            _ = try DogfoodReport.generate(db: db, days: Int.max)
            XCTAssertTrue(false, "oversized reporting windows must be rejected")
        } catch DogfoodReport.Invalid.days {}
    }
    func testFirstHandoffGuideUsesRealEventsAndSurvivesRestart() throws {
        let suite = "beamhop-onboarding-test-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw NSError(domain: "TrialFixture", code: 1) }
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = OnboardingModel(defaults: defaults)
        XCTAssertTrue(model.nextStep == .permission, "permission is measured, not assumed from onboarding history")
        model.refreshAccessibility(granted: true)
        XCTAssertTrue(model.nextStep == .capture, "permission refresh advances the guide")
        model.captureSaved()
        XCTAssertTrue(model.nextStep == .receiver, "only a saved real capture advances capture progress")
        model.observe(HopActivity(.started, id: "first"))
        model.observe(HopActivity(.failed, id: "first"))
        XCTAssertTrue(
            model.nextStep == .recovery && model.progress.needsRecovery && !model.progress.hasTransportReceipt,
            "failure preserves recovery guidance, not completion")
        model.observe(HopActivity(.recovered, id: "first"))
        XCTAssertTrue(!model.progress.needsRecovery, "restoring the failed backup allows another attempt")
        model.observe(HopActivity(.started, id: "second"))
        model.observe(HopActivity(.copied, id: "second"))
        model.observe(HopActivity(.failed, id: "first"))
        XCTAssertTrue(
            model.progress.lastReceipt == .copied && !model.progress.needsRecovery,
            "a late old failure cannot overwrite the newer guide state")
        XCTAssertTrue(model.nextStep == .manualSubmission, "copied is still a manual submission step")
        model.observe(HopActivity(.started, id: "third"))
        XCTAssertTrue(!model.progress.hasTransportReceipt && model.nextStep == .receiver, "a previous copy is not readiness for a newer pending attempt")
        model.observe(HopActivity(.prepared, id: "third"))
        let reopened = OnboardingModel(defaults: defaults)
        XCTAssertTrue(reopened.progress == model.progress, "real workflow progress survives restart")
        XCTAssertTrue(reopened.nextStep == .permission, "permission must be freshly checked after restart")
        reopened.refreshAccessibility(granted: true)
        XCTAssertTrue(reopened.nextStep == .manualSubmission, "rechecking permission does not erase progress")
        reopened.refreshAccessibility(granted: false)
        XCTAssertTrue(
            reopened.nextStep == .permission && reopened.progress.hasCaptured,
            "revocation returns to permission without losing prior capture evidence")
    }
    func testPocketReuseRetriesAndInterruptedAttempts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try Database(path: directory.appendingPathComponent("fixture.sqlite"))
        let library = try HopLibrary(db)
        let route = HopRoute(target: .clipboard)
        let a = HopDraft(materials: [HopMaterial(text: "a")], route: route)
        let b = HopDraft(materials: [HopMaterial(text: "b")], route: route)
        try library.hold(a)
        try library.hold(a)
        try library.hold(b)
        try library.importLegacyDraft(HopDraft(materials: [HopMaterial(text: "imported")], route: route))
        let failed = try library.beginBatch([a, b], route: route)
        try library.finish(failed.id, status: .failed)
        var report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(report.hops.savedDrafts == 2, "same draft updates and legacy imports do not inflate Pocket saves")
        XCTAssertTrue(report.hops.reusedDrafts == 0, "a failed batch is not a completed Pocket handoff")
        let retry = try library.beginBatch([a, b], route: route)
        try library.finish(retry.id, status: .copied)
        report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(
            retry.id != failed.id && report.hops.attempts == 2, "retry is a fresh attempt, not a new task claim")
        XCTAssertTrue(
            report.hops.pocketHandoffs == 2 && report.hops.reusedDrafts == 2,
            "batch denominator and distinct reused drafts stay separate")
        try library.recover(failed)
        _ = try library.begin(a)
        _ = try HopLibrary(db)
        report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(report.hops.recoveredBackups == 1, "backup recovery is counted separately")
        XCTAssertTrue(
            report.hops.failed == 1 && report.hops.interrupted == 1 && report.hops.pending == 0,
            "restart unknown status is not a proven delivery failure")
    }
    func testHopReceiptsStaySeparateFromLegacyDeliveriesAndResults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try Database(path: directory.appendingPathComponent("fixture.sqlite"))
        let library = try HopLibrary(db)
        let draft = HopDraft(
            materials: [HopMaterial(text: "PRIVATE BODY")], route: .init(target: .clipboard), requestsResultReturn: true
        )
        let copied = try library.begin(draft)
        try library.finish(copied.id, status: .copied)
        try library.finish(copied.id, status: .copied)
        let prepared = try library.begin(draft)
        try library.finish(prepared.id, status: .prepared)
        let failed = try library.begin(draft)
        try library.finish(failed.id, status: .failed, detail: "PRIVATE ERROR")
        try HandoffResultStore(db.queue).insert(
            HandoffResult(handoffID: copied.id, agent: "fixture", content: "PRIVATE CONCLUSION"))
        let capture = Capture(
            source: .ax, appBundleID: "fixture", appName: "Fixture", selectedText: "source", pid: 1,
            captureMethod: "fixture")
        let captures = CaptureStore(db)
        try captures.insert(capture)
        try captures.recordDelivery(Delivery(captureID: capture.id, target: .kimiWork, status: .success))
        try captures.recordDelivery(Delivery(captureID: capture.id, target: .kimiWork, status: .failed))
        var report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(report.hops.attempts == 3, "one logical attempt per handoff, not delivery rows")
        XCTAssertTrue(
            report.hops.copied == 1 && report.hops.prepared == 1 && report.hops.failed == 1,
            "transport outcomes stay separate")
        XCTAssertTrue(
            report.hops.pending == 0 && report.hops.returnedHandoffs == 1,
            "a conclusion does not change transport receipts")
        XCTAssertTrue(report.attempts == 2, "legacy delivery rows keep their own denominator")
        try library.deleteRecords([copied.id, prepared.id, failed.id])
        report = try DogfoodReport.generate(db: db)
        XCTAssertTrue(
            report.hops.attempts == 3 && report.hops.copied == 1, "deleting backups does not erase usage telemetry")
        let text = report.gateTable()
        XCTAssertTrue(
            text.contains("not task completion") && text.contains("Legacy delivery rows"),
            "report labels do not claim global success")
        XCTAssertTrue(!text.contains("PRIVATE"), "aggregate report excludes source and result content")
    }
}
