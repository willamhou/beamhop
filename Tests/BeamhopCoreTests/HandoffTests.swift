import XCTest
import GRDB
@testable import BeamhopCore

final class HandoffTests: XCTestCase {
    private func capture(_ text: String) -> Capture {
        Capture(source: .ax, appBundleID: "com.apple.Safari", appName: "Safari",
                windowTitle: text, url: "https://example.com/\(text)", selectedText: text,
                pid: 1, captureMethod: "ax")
    }

    func testBatchRendersAllMaterialsOnceInSelectionOrder() {
        let first = capture("first"), second = capture("second")
        let h = Handoff(items: [.init(capture: first, note: "note one"),
                                .init(capture: second, note: "note two")])
        let markdown = h.markdown
        XCTAssertTrue(markdown.contains("https://example.com/first"))
        XCTAssertTrue(markdown.contains("https://example.com/second"))
        XCTAssertTrue(markdown.contains("note one"))
        XCTAssertTrue(markdown.hasSuffix("note two\n"))
        XCTAssertLessThan(markdown.range(of: "<selected>\nfirst")!.lowerBound,
                          markdown.range(of: "<selected>\nsecond")!.lowerBound)
        XCTAssertTrue(h.claudeTrigger.contains("fetch_capture('\(first.id)')"))
        XCTAssertTrue(h.claudeTrigger.contains("fetch_capture('\(second.id)')"))
        XCTAssertEqual(Handoff(items: [.init(capture: first)]).markdown,
                       PromptRenderer.fullMarkdown(first, userNote: nil))
    }

    func testChangingReceiverInvalidatesPreviousAcknowledgment() {
        let work = Work(name: "Fix capture", boundTarget: .claudeCode, confirmedTarget: .claudeCode)
        var delivered: [DeliveryTarget?] = []
        let model = CapturePanelModel(capture: capture("a"), initialTarget: .chatgptDesktop,
                                      boundWork: work, onConfirm: { t, _ in delivered.append(t) }, onCancel: {})
        model.confirm()
        XCTAssertTrue(model.rebindAcknowledged)
        model.selectedTarget = .kimiWork
        XCTAssertFalse(model.rebindAcknowledged)
        model.confirm()
        XCTAssertTrue(delivered.isEmpty)
        model.confirm()
        XCTAssertEqual(delivered, [.kimiWork])
    }

    func testInboxOnlyBypassesRebindAndChangingWorkResolvesItsOwnBinding() {
        let a = Work(name: "A", boundTarget: .kimiWork, confirmedTarget: .claudeCode)
        let b = Work(name: "B", boundTarget: .chatgptDesktop, confirmedTarget: .chatgptDesktop)
        var deliveries = 0
        let model = CapturePanelModel(capture: capture("a"), initialTarget: .kimiWork,
                                      boundWork: a, availableWorks: [a, b],
                                      onConfirm: { _, _ in deliveries += 1 }, onCancel: {})
        model.selectedTarget = nil
        XCTAssertFalse(model.receiverChanged)
        model.confirm()
        XCTAssertEqual(deliveries, 1)
        model.chooseWork(b)
        XCTAssertEqual(model.boundWork?.id, b.id)
        XCTAssertEqual(model.selectedTarget, .chatgptDesktop)
        XCTAssertFalse(model.receiverChanged)
        model.chooseTool(.clipboard)
        XCTAssertNil(model.boundWork)
        XCTAssertTrue(model.workName.isEmpty)
    }

    func testUnavailableNamedReceiverDoesNotRouteToAnotherApp() {
        let work = Work(name: "A", boundTarget: .kimiWork, confirmedTarget: .kimiWork)
        let model = CapturePanelModel(capture: capture("a"), initialTarget: .kimiWork,
                                      visibleTargets: [.chatgptDesktop, .clipboard], boundWork: work,
                                      onConfirm: { _, _ in }, onCancel: {})
        XCTAssertNil(model.selectedTarget)
    }

    func testPlainToolHandoffClearsPreviousWorkMemory() {
        var memory = TargetMemory()
        memory.markSucceeded(.claudeCode, workName: " A ")
        XCTAssertEqual(memory.lastWorkName, "A")
        memory.markSucceeded(.kimiWork)
        XCTAssertEqual(memory.last, .kimiWork)
        XCTAssertNil(memory.lastWorkName)
    }

    private func withStore(_ body: (PocketStore, CaptureStore) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try BeamhopCore.Database(path: dir.appendingPathComponent("test.sqlite"))
        try body(PocketStore(db), CaptureStore(db))
    }

    func testPocketKeepsSelectionUntilSuccessAndOnlyRemovesSelectedItems() throws {
        try withStore { pocket, captures in
            let a = capture("a"), b = capture("b"), c = capture("c")
            for cap in [a, b, c] { try captures.insert(cap) }
            let first = try pocket.hold(captureID: a.id, note: "note", intendedTarget: .clipboard, workName: "A")
            let second = try pocket.hold(captureID: b.id, note: nil, intendedTarget: .clipboard, workName: "A")
            let third = try pocket.hold(captureID: c.id, note: nil, intendedTarget: .kimiWork, workName: "B")
            let model = PocketModel()
            var completion: ((Bool) -> Void)?
            var batches: [[String]] = []
            var count = 0
            model.configure(store: pocket, onDeliver: { batch, target, done in
                XCTAssertEqual(target, .clipboard)
                batches.append(batch.map { $0.0.id })
                completion = done
            }, onCountChange: { count = $0 })
            model.reload()
            model.toggle(second.id)
            model.toggle(first.id)
            model.deliverSelection()
            XCTAssertTrue(model.isDelivering)
            XCTAssertEqual(model.count, 3)
            XCTAssertEqual(batches, [[first.id, second.id]], "hold order survives reverse selection")
            model.deliverSelection()
            XCTAssertEqual(batches.count, 1, "double clicks cannot enqueue a duplicate")
            completion?(false)
            XCTAssertEqual(model.selectedIDs, [first.id, second.id])
            XCTAssertEqual(try pocket.count(), 3)
            XCTAssertNotNil(model.error)
            model.deliverSelection()
            completion?(true)
            XCTAssertEqual(model.items.map { $0.0.id }, [third.id])
            XCTAssertEqual(count, 1)
            XCTAssertTrue(model.selectedIDs.isEmpty)
            XCTAssertEqual(try captures.count(), 3, "removing held items never deletes originals")
            XCTAssertEqual(try captures.fetch(id: a.id)?.selectedText, "a")
        }
    }

    func testSameAppDoesNotCombineDifferentWorksAndUndecidedRequiresChoice() throws {
        try withStore { pocket, captures in
            let a = capture("a"), b = capture("b"), c = capture("c")
            for cap in [a, b, c] { try captures.insert(cap) }
            let first = try pocket.hold(captureID: a.id, note: nil, intendedTarget: .kimiWork, workName: "A")
            let second = try pocket.hold(captureID: b.id, note: nil, intendedTarget: .kimiWork, workName: "B")
            let unknown = try pocket.hold(captureID: c.id, note: nil, intendedTarget: nil)
            let model = PocketModel()
            model.configure(store: pocket, onDeliver: { _, _, _ in XCTFail("must not send") })
            model.reload()
            model.toggle(first.id)
            model.toggle(second.id)
            XCTAssertTrue(model.hasMixedDestinations)
            XCTAssertFalse(model.canDeliver)
            model.deliverSelection()
            model.toggle(first.id)
            model.toggle(second.id)
            model.toggle(unknown.id)
            XCTAssertNil(model.selectedTarget)
            XCTAssertFalse(model.canDeliver)
            model.selectedTarget = .clipboard
            XCTAssertTrue(model.canDeliver)
        }
    }

    func testV6PocketMigrationPreservesExistingMaterial() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("old.sqlite")
        let queue = try DatabaseQueue(path: path.path)
        try Migrations.migrator().migrate(queue, upTo: "v6")
        let cap = capture("legacy")
        try queue.write { db in
            try cap.insert(db)
            try db.execute(sql: "INSERT INTO pocket_items(id,capture_id,note,intended_target,position,created_at) VALUES(?,?,?,?,?,?)",
                           arguments: ["old-item", cap.id, "keep me", "clipboard", 1, 1])
        }
        try queue.close()
        let db = try BeamhopCore.Database(path: path)
        let legacy = try XCTUnwrap(PocketStore(db).stack().first)
        XCTAssertEqual(legacy.note, "keep me")
        XCTAssertEqual(legacy.captureID, cap.id)
        XCTAssertNil(legacy.workName)
        try CaptureStore(db).setUserNote("saved draft", captureID: cap.id)
        XCTAssertEqual(try CaptureStore(db).fetch(id: cap.id)?.userNote, "saved draft")
    }

    func testTransportStatusDoesNotImplyAgentExecution() throws {
        XCTAssertEqual(DeliveryStatus.prepared.displayName, "Prepared · awaiting your send")
        XCTAssertEqual(DeliveryStatus.copied.displayName, "Copied")
        for status in [DeliveryStatus.prepared, .copied, .success, .failed] {
            XCTAssertEqual(try JSONDecoder().decode(DeliveryStatus.self, from: JSONEncoder().encode(status)), status)
        }
    }
    func testUnavailableReceiverCannotSendOrForgetHeldIntent() {
        var confirmations = 0
        var held: DeliveryTarget?
        let model = CapturePanelModel(capture: capture("a"), initialTarget: .kimiWork,
                                      visibleTargets: [.clipboard],
                                      onConfirm: { _, _ in confirmations += 1 }, onCancel: {},
                                      onHold: { target, _ in held = target })
        XCTAssertFalse(model.canConfirm)
        model.confirm()
        XCTAssertEqual(confirmations, 0)
        model.hold()
        XCTAssertEqual(held, .kimiWork)
        XCTAssertFalse(model.handleShortcut("2"))
        XCTAssertTrue(model.handleShortcut("3"))
        XCTAssertEqual(model.selectedTarget, .clipboard)
        XCTAssertTrue(model.canConfirm)
        model.confirm()
        XCTAssertEqual(confirmations, 1)
    }

    func testPocketKeepsAnExplicitReceiverWithinTheSameWork() throws {
        try withStore { pocket, captures in
            let a = capture("a"), b = capture("b")
            for cap in [a, b] { try captures.insert(cap) }
            let one = try pocket.hold(captureID: a.id, note: nil, intendedTarget: nil)
            let two = try pocket.hold(captureID: b.id, note: nil, intendedTarget: nil)
            let model = PocketModel()
            model.configure(store: pocket, onDeliver: { _, _, _ in })
            model.reload()
            model.toggle(one.id)
            model.selectedTarget = .clipboard
            model.toggle(two.id)
            XCTAssertEqual(model.selectedTarget, .clipboard)
            XCTAssertTrue(model.canDeliver)
            model.toggle(one.id)
            XCTAssertEqual(model.selectedTarget, .clipboard)
            model.toggle(two.id)
            XCTAssertNil(model.selectedTarget)
        }
    }

    func testDelayedReceiptCannotConfirmANewerReceiver() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try BeamhopCore.Database(path: directory.appendingPathComponent("work.sqlite"))
        let store = WorkStore(db)
        let work = try store.register(name: "A", boundTo: .claudeCode)
        _ = try store.rebind(id: work.id, to: .kimiWork)
        _ = try store.rebind(id: work.id, to: .chatgptDesktop)
        try store.confirm(id: work.id, expectedTarget: .kimiWork)
        XCTAssertTrue(try XCTUnwrap(store.fetch(id: work.id)).needsConfirmation)
        try store.confirm(id: work.id, expectedTarget: .chatgptDesktop)
        XCTAssertFalse(try XCTUnwrap(store.fetch(id: work.id)).needsConfirmation)
    }

}
