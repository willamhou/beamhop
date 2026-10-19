import XCTest
import Foundation
@testable import BeamhopCore

final class FocusInboxRegressionTests: XCTestCase {
    func testSelfCaptureGuardWorksWithOrWithoutBundle() {
        XCTAssertTrue(CaptureFocusPolicy.isSelf(sourcePID: 42, sourceBundleID: "unknown", ownPID: 42))
        XCTAssertTrue(CaptureFocusPolicy.isSelf(sourcePID: 43, sourceBundleID: "com.beamhop.app", ownPID: 42))
        XCTAssertFalse(CaptureFocusPolicy.isSelf(sourcePID: 43, sourceBundleID: "com.apple.Safari", ownPID: 42))
    }

    func testFocusRecoveryDoesNotStealFromDestinationOrOtherWindows() {
        func restore(_ front: Int32?, terminated: Bool = false, window: Bool = false,
                     source: Int32 = 7) -> Bool {
            CaptureFocusPolicy.shouldRestore(sourcePID: source, ownPID: 42, frontmostPID: front,
                                             sourceTerminated: terminated, hasVisibleBeamhopWindow: window)
        }
        XCTAssertTrue(restore(42))                     // Esc / Inbox-only / clipboard fallback
        XCTAssertFalse(restore(9))                     // delivery target or clicked app
        XCTAssertFalse(restore(7))                     // source already frontmost
        XCTAssertFalse(restore(nil))                   // no foreground app
        XCTAssertFalse(restore(42, terminated: true))  // source exited
        XCTAssertFalse(restore(42, window: true))      // Inbox or a newer panel is in use
        XCTAssertFalse(restore(42, source: 42))        // never restore self
    }

    func testInboxSeesExternalWritebackBeyondSummaryWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("inbox.sqlite")
        let db = try Database(path: path)
        let store = CaptureStore(db)
        let events = EventStore(db)
        var rows: [Capture] = []
        for index in 0..<61 {
            let row = Capture(createdAt: Int64(1000 + index), source: .ax,
                              appBundleID: "com.apple.Safari", appName: "Safari",
                              windowTitle: "Document \(index)", pid: 7, captureMethod: "ax")
            try store.insert(row)
            rows.append(row)
        }
        let origin = rows[0] // last row of the newest-first list, beyond prefix(50)
        let other = rows[1]
        let model = InboxModel()
        model.configure(store: store, events: events, onDeliver: { _, _ in })
        model.reload()
        model.selectedID = origin.id
        XCTAssertTrue(model.selectedResults.isEmpty)
        let eventCount = try events.count()

        // Separate connection, the same path used by the external MCP process.
        let writer = try ResultStore.open(path: path)
        let result = CaptureResult(originCaptureID: origin.id, agent: "codex", sessionID: "test-session",
                                   content: "结论\n" + String(repeating: "证据", count: 1500), createdAt: 3000)
        try writer.insert(result)
        try writer.insert(CaptureResult(originCaptureID: other.id, agent: "kimi", content: "other"))
        try store.recordDelivery(Delivery(captureID: origin.id, target: .claudeCode,
                                          deliveredAt: 2000, status: .success))
        model.refreshSelectedDetails()
        XCTAssertEqual(model.selectedResults, [result])
        XCTAssertEqual(model.resultCounts[origin.id], 1)
        XCTAssertEqual(model.deliveries[origin.id]?.count, 1)
        XCTAssertEqual(try events.count(), eventCount, "Polling must not count as visits/searches/views")

        model.selectedID = other.id
        XCTAssertEqual(model.selectedResults.first?.content, "other")
        model.selectedID = nil
        XCTAssertTrue(model.selectedResults.isEmpty)
        model.selectedID = origin.id
        model.softDelete(origin)
        XCTAssertNil(model.selectedID)
        XCTAssertTrue(model.selectedResults.isEmpty)
        model.selectedID = other.id
        try db.queue.write { try $0.execute(sql: "DROP TABLE results") }
        model.refreshSelectedDetails()
        XCTAssertNotNil(model.detailErrorMessage)
        XCTAssertTrue(model.selectedResults.isEmpty, "A read error must not show a stale conclusion")
    }

    func testInboxConclusionPaginationAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureStore(try Database(path: directory.appendingPathComponent("inbox.sqlite")))
        let origin = Capture(source: .ax, appBundleID: "app", appName: "App", pid: 7, captureMethod: "ax")
        try store.insert(origin)
        for index in 0..<101 {
            try store.insertResult(CaptureResult(originCaptureID: origin.id, agent: "codex",
                                                 content: "\(index)", createdAt: Int64(index)))
        }
        let model = InboxModel()
        model.configure(store: store, events: nil, onDeliver: { _, _ in })
        model.reload()
        model.selectedID = origin.id
        XCTAssertEqual(model.resultCounts[origin.id], 101)
        XCTAssertEqual(model.selectedResults.count, 100)
        XCTAssertTrue(model.hasMoreResults)
        model.loadMoreResults()
        XCTAssertEqual(model.selectedResults.count, 101)
        XCTAssertFalse(model.hasMoreResults)
        model.reload()
        XCTAssertEqual(model.selectedID, origin.id)
        XCTAssertEqual(model.selectedResults.count, 101)
    }

    func testTimelineOrderAndSameMillisecondTies() {
        let delivery = Delivery(id: 1, captureID: "cap", target: .claudeCode,
                                deliveredAt: 200, status: .success)
        let earlier = CaptureResult(id: "res_a", originCaptureID: "cap", agent: "codex",
                                    content: "a", createdAt: 100)
        let tieB = CaptureResult(id: "res_c", originCaptureID: "cap", agent: "kimi",
                                 content: "b", createdAt: 200)
        let tieA = CaptureResult(id: "res_b", originCaptureID: "cap", agent: "codex",
                                 content: "c", createdAt: 200)
        XCTAssertEqual(TimelineBuilder.entries(deliveries: [delivery], results: [tieB, earlier, tieA]),
                       [.result(earlier), .delivery(delivery), .result(tieA), .result(tieB)])
        XCTAssertTrue(TimelineBuilder.entries(deliveries: [], results: []).isEmpty)
    }
}
