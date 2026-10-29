import XCTest

@testable import BeamhopCore

final class TaskRelayTests: XCTestCase {
    func testDeletedTaskFilter() throws {

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try HopLibrary(
            Database(path: directory.appendingPathComponent("filter.sqlite")))
        let unassigned = HopDraft(materials: [HopMaterial(text: "must stay discoverable")])
        try library.hold(unassigned)
        var assigned = HopDraft(materials: [HopMaterial(text: "task")])
        assigned.task = HopTask(title: "Temporary task")
        let record = try library.begin(assigned)
        try library.finish(record.id, status: .copied)
        let pocket = HopPocketModel(library: library)
        pocket.taskIDFilter = assigned.task?.id
        try library.deleteRecords([record.id])
        XCTAssertTrue(
            pocket.taskIDFilter == nil && pocket.drafts == [unassigned],
            "deleting last task restores access to unassigned drafts")
    }
    func testLegacyTaskRelay() throws {

        let legacy =
            #"{"id":"old-draft","materials":[],"instruction":"legacy literal","route":{"project":"","session":"currentWindow"}}"#
        let draft = try JSONDecoder().decode(HopDraft.self, from: Data(legacy.utf8))
        XCTAssertTrue(
            draft.task == nil && draft.relay == nil && !draft.requestsResultReturn,
            "old draft does not fabricate task, context or consent")
        let receipt = "{\"id\":\"old-record\",\"draft\":" + legacy + ",\"status\":\"copied\"}"
        let record = try JSONDecoder().decode(HopRecord.self, from: Data(receipt.utf8))
        XCTAssertTrue(
            record.outgoingText == "legacy literal",
            "old receipt does not gain retroactive metadata")
        let frozen = HopRecord(draft: draft, status: .copied)
        let reopened = try JSONDecoder().decode(HopRecord.self, from: JSONEncoder().encode(frozen))
        XCTAssertTrue(
            reopened.outgoingText == frozen.outgoingText && reopened.draft.task == nil,
            "unassociated identity-era receipts round-trip unchanged")
    }
    func testTaskBatchAndPresentation() throws {

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = try HopLibrary(
            Database(path: directory.appendingPathComponent("batch.sqlite")))
        let task = HopTask(title: "Same title")
        let other = HopTask(title: "Same title")
        let route = HopRoute(target: .clipboard)
        var a = HopDraft(materials: [HopMaterial(text: "a")], route: route)
        a.task = task
        a.relay = HopRelayContext(text: "A relay")
        var b = HopDraft(materials: [HopMaterial(text: "b")], route: route)
        b.task = other
        b.relay = HopRelayContext(text: "B relay")
        try library.hold(a)
        try library.hold(b)
        let pocket = HopPocketModel(library: library)
        pocket.onDeliver = { _, _ in }
        pocket.selectAll()
        XCTAssertTrue(
            pocket.mixedTasks && !pocket.canDeliver,
            "same titles do not merge distinct task identities")
        do {
            _ = try library.beginBatch([a, b], route: route)
            XCTAssertTrue(false, "mixed-task batches must fail before saving a receipt")
        } catch HopLibrary.TaskError.mixedTasks {}
        XCTAssertTrue(library.state.records.isEmpty, "blocked batch leaves no receipt")
        b.task = task
        try library.hold(b)
        let batch = try library.beginBatch([a, b], route: route)
        XCTAssertTrue(
            batch.draft.task == task && batch.outgoingText.contains("A relay")
                && batch.outgoingText.contains("B relay"), "same-task batch preserves each relay")
        try library.finish(batch.id, status: .failed)
        pocket.taskIDFilter = other.id
        XCTAssertTrue(pocket.records.isEmpty, "history filters by identity, not title")
        pocket.taskIDFilter = task.id
        XCTAssertTrue(
            pocket.records.map(\.id) == [batch.id], "matching task history remains visible")
        let source = Capture(
            source: .ax, appBundleID: "fixture", appName: "Fixture", pid: 1,
            captureMethod: "fixture")
        let panel = CapturePanelModel(
            capture: source, initialTarget: .clipboard, onConfirm: { _, _ in }, onCancel: {})
        panel.restore(a)
        panel.relayText = "edited relay"
        XCTAssertTrue(
            panel.snapshot.task == task && panel.snapshot.relay?.text == "edited relay",
            "panel editing retains task linkage")
        XCTAssertTrue(
            panel.snapshot.outgoingText.contains("edited relay"),
            "preview is the actual editable outgoing package")
        panel.createTask(title: "  New task  ")
        XCTAssertTrue(
            panel.taskOptions.contains { $0.id == panel.snapshot.task?.id },
            "new task remains represented in the picker before a catalog refresh")
        XCTAssertTrue(
            panel.snapshot.task?.title == "New task" && panel.snapshot.task?.id != task.id,
            "explicit new task creates an independent identity")
    }
    func testTaskContinuationPreservesInputAndScopesConclusions() throws {

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try Database(path: directory.appendingPathComponent("relay.sqlite"))
        let library = try HopLibrary(database)
        let task = HopTask(title: "Focus")
        var draft = HopDraft(materials: [HopMaterial(text: "selected")], requestsResultReturn: true)
        draft.task = task
        draft.relay = HopRelayContext(text: "Constraints: no auto-send")
        try library.start(draft)
        let first = try library.begin(draft)
        draft.relay?.text = "later constraint"
        try library.saveActive(draft)
        try library.finish(first.id, status: .copied)
        XCTAssertTrue(library.state.active == draft, "relay-only edits survive late completion")
        let store = HandoffResultStore(database.queue)
        let result = HandoffResult(handoffID: first.id, agent: "fixture", content: "suspected race")
        try store.insert(result)
        try library.continueTask(handoffID: first.id, resultID: result.id)
        let continued = library.state.active!
        XCTAssertTrue(
            continued.task == task && continued.id != first.draft.id,
            "continuation keeps task, creates a new draft")
        XCTAssertTrue(!continued.requestsResultReturn, "new continuation defaults return off")
        XCTAssertTrue(
            continued.relay?.text.contains("suspected race") == true,
            "only selected conclusion becomes editable relay")
        XCTAssertTrue(
            continued.relay?.text.contains("Constraints: no auto-send") == true,
            "continuation retains earlier relay constraints")
        XCTAssertTrue(continued.relay?.sourceResultID == result.id, "relay records selected source")
        XCTAssertTrue(library.state.pocket.contains(draft), "continuation parks unrelated edits")
        let retry = try library.begin(continued)
        XCTAssertTrue(
            retry.id != first.id && library.history(taskID: task.id).count == 2,
            "task spans independent attempts")
        try library.finish(retry.id, status: .failed)
        let reopened = try HopLibrary(database)
        XCTAssertTrue(
            reopened.state == library.state && reopened.tasks == [task],
            "task and relay survive restart")
        do {
            try reopened.continueTask(handoffID: retry.id, resultID: result.id)
            XCTAssertTrue(false, "a result from another attempt must be rejected")
        } catch HopLibrary.TaskError.unavailableSource {}
        XCTAssertTrue(
            reopened.state.active == continued, "rejected source never overwrites active input")
    }
    func testTaskRelayFreezesLiteralEditedOutputAndIndependentConsent() throws {
        let task = HopTask(title: "Fix focus")
        var draft = HopDraft(
            materials: [HopMaterial(text: "literal material")], instruction: "/review\nkeep this")
        draft.task = task
        draft.relay = HopRelayContext(text: "Agent claim, not verified: suspected race")
        let record = HopRecord(draft: draft)
        XCTAssertTrue(record.outgoingText.hasPrefix("/review\nkeep this\n\nSource:"))
        XCTAssertTrue(record.outgoingText.contains("Agent claim, not verified: suspected race"))
        XCTAssertTrue(record.outgoingText.contains("Task ID: \(task.id)"))
        XCTAssertFalse(record.acceptsResultReturn)
        draft.relay?.text = "newer edit"
        XCTAssertFalse(record.outgoingText.contains("newer edit"))
        XCTAssertEqual(record.draft.task, task)
    }
}
