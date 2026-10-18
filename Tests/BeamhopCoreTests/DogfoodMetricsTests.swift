import XCTest
import Foundation
@testable import BeamhopCore

/// Mirror of the SelfTest "Phase 1.5: EventStore + DogfoodReport" section (runs where Xcode
/// is available; SelfTest is the CLT fallback).
final class DogfoodMetricsTests: XCTestCase {
    var tmpDir: URL!
    var dbURL: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("beamhop-dogfood-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        dbURL = tmpDir.appendingPathComponent("inbox.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testEventStoreRoundTripAndPrune() throws {
        let db = try Database(path: dbURL)
        let events = EventStore(db)
        events.record(name: EventStore.Name.captureCompleted, detail: "method=ax ms=42",
                      captureID: "cap_x", date: Date())
        events.record(name: EventStore.Name.inboxOpened, date: Date())
        XCTAssertEqual(try events.count(), 2)

        events.record(name: EventStore.Name.inboxOpened, date: Date().addingTimeInterval(-400 * 86400))
        XCTAssertEqual(try events.prune(retentionDays: 180), 1)
        XCTAssertEqual(try events.count(), 2, "recent events survive prune")
    }

    func testDogfoodReportMath() throws {
        let db = try Database(path: dbURL)
        let store = CaptureStore(db)
        let events = EventStore(db)

        let cap = Capture(id: ULID.captureID(), source: .ax, appBundleID: "com.apple.Safari",
                          appName: "Safari", windowTitle: "t", selectedText: "s", pid: 1,
                          captureMethod: "ax")
        try store.insert(cap)

        events.record(name: EventStore.Name.captureCompleted, date: Date())
        events.record(name: EventStore.Name.captureDuplicate, date: Date())
        for i in 1...20 {
            events.record(name: EventStore.Name.panelShown, detail: "ms=\(i)", captureID: cap.id, date: Date())
        }
        events.record(name: EventStore.Name.inboxOpened, date: Date())
        events.record(name: EventStore.Name.inboxOpened, date: Date().addingTimeInterval(-86400))

        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .success, durationMs: 300))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .success, durationMs: 500))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .claudeCode, status: .failed,
                                          errorMessage: "no terminal", durationMs: 900))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .chatgptDesktop, status: .failed, durationMs: 700))
        try store.recordDelivery(Delivery(captureID: cap.id, target: .clipboard, status: .success))

        let r = try DogfoodReport.generate(db: db, days: 14)
        XCTAssertEqual(r.pressCount, 2)
        XCTAssertEqual(r.panelP95ms, 19)
        XCTAssertEqual(r.attempts, 4, "clipboard rows are not chosen-target attempts")
        XCTAssertEqual(r.chosenTargetFailures, 2)
        XCTAssertEqual(r.readableFailures, 1)
        XCTAssertEqual(r.successRate ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(r.avgDeliveryMs, 600)
        XCTAssertEqual(r.inboxOpenedCount, 2)
        XCTAssertEqual(r.inboxVisitsPerWeek, 1.0, accuracy: 0.0001)
        XCTAssertEqual(r.inboxTotalCaptures, 1)
        XCTAssertTrue(r.gateTable().contains("≥ 95%"))
    }

    func testDeliveryDurationRoundTrips() throws {
        let db = try Database(path: dbURL)
        let store = CaptureStore(db)
        let cap = Capture(id: ULID.captureID(), source: .ax, appBundleID: "a.b", appName: "A",
                          windowTitle: nil, selectedText: "s", pid: 1, captureMethod: "ax")
        try store.insert(cap)
        try store.recordDelivery(Delivery(captureID: cap.id, target: .kimiWork, status: .success, durationMs: 1234))
        let d = try store.deliveries(captureID: cap.id).first
        XCTAssertEqual(d?.durationMs, 1234)
    }
}
