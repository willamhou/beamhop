import BeamhopCore
import Foundation

private func testLegacyTaskRelay() throws {

    let legacy =
        #"{"id":"old-draft","materials":[],"instruction":"legacy literal","route":{"project":"","session":"currentWindow"}}"#
    let draft = try JSONDecoder().decode(HopDraft.self, from: Data(legacy.utf8))
    check(
        draft.task == nil && draft.relay == nil && !draft.requestsResultReturn,
        "old draft does not fabricate task, context or consent")
    let receipt = "{\"id\":\"old-record\",\"draft\":" + legacy + ",\"status\":\"copied\"}"
    let record = try JSONDecoder().decode(HopRecord.self, from: Data(receipt.utf8))
    check(record.outgoingText == "legacy literal", "old receipt does not gain retroactive metadata")
    let frozen = HopRecord(draft: draft, status: .copied)
    let reopened = try JSONDecoder().decode(HopRecord.self, from: JSONEncoder().encode(frozen))
    check(
        reopened.outgoingText == frozen.outgoingText && reopened.draft.task == nil,
        "unassociated identity-era receipts round-trip unchanged")
}

func runTaskRelayRegression() throws {
    let task = HopTask(title: "Fix focus")
    var draft = HopDraft(
        materials: [HopMaterial(text: "literal material")], instruction: "/review\nkeep this")
    draft.task = task
    draft.relay = HopRelayContext(text: "Agent claim, not verified: suspected race")
    let record = HopRecord(draft: draft)
    guard record.outgoingText.hasPrefix("/review\nkeep this\n\nSource:"),
        record.outgoingText.contains("Agent claim, not verified: suspected race"),
        record.outgoingText.contains("Task ID: \(task.id)"), !record.acceptsResultReturn
    else {
        throw NSError(domain: "TaskRelayRegression", code: 1)
    }
    draft.relay?.text = "newer edit"
    guard !record.outgoingText.contains("newer edit"), record.draft.task == task else {
        throw NSError(domain: "TaskRelayRegression", code: 2)
    }
    print("PASS: task relay freezes literal edited output and independent consent")
    try testTaskContinuation()
    try testTaskBatchAndPresentation()
    try testLegacyTaskRelay()
    try testDeletedTaskFilter()
}

private func testDeletedTaskFilter() throws {

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = try HopLibrary(Database(path: directory.appendingPathComponent("filter.sqlite")))
    let unassigned = HopDraft(materials: [HopMaterial(text: "must stay discoverable")])
    try library.hold(unassigned)
    var assigned = HopDraft(materials: [HopMaterial(text: "task")])
    assigned.task = HopTask(title: "Temporary task")
    let record = try library.begin(assigned)
    try library.finish(record.id, status: .copied)
    let pocket = HopPocketModel(library: library)
    pocket.taskIDFilter = assigned.task?.id
    try library.deleteRecords([record.id])
    check(
        pocket.taskIDFilter == nil && pocket.drafts == [unassigned],
        "deleting last task restores access to unassigned drafts")
}

private func testTaskBatchAndPresentation() throws {

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = try HopLibrary(Database(path: directory.appendingPathComponent("batch.sqlite")))
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
    check(
        pocket.mixedTasks && !pocket.canDeliver, "same titles do not merge distinct task identities"
    )
    do {
        _ = try library.beginBatch([a, b], route: route)
        check(false, "mixed-task batches must fail before saving a receipt")
    } catch HopLibrary.TaskError.mixedTasks {}
    check(library.state.records.isEmpty, "blocked batch leaves no receipt")
    b.task = task
    try library.hold(b)
    let batch = try library.beginBatch([a, b], route: route)
    check(
        batch.draft.task == task && batch.outgoingText.contains("A relay")
            && batch.outgoingText.contains("B relay"), "same-task batch preserves each relay")
    try library.finish(batch.id, status: .failed)
    pocket.taskIDFilter = other.id
    check(pocket.records.isEmpty, "history filters by identity, not title")
    pocket.taskIDFilter = task.id
    check(pocket.records.map(\.id) == [batch.id], "matching task history remains visible")
    let source = Capture(
        source: .ax, appBundleID: "fixture", appName: "Fixture", pid: 1, captureMethod: "fixture")
    let panel = CapturePanelModel(
        capture: source, initialTarget: .clipboard, onConfirm: { _, _ in }, onCancel: {})
    panel.restore(a)
    panel.relayText = "edited relay"
    check(
        panel.snapshot.task == task && panel.snapshot.relay?.text == "edited relay",
        "panel editing retains task linkage")
    check(
        panel.snapshot.outgoingText.contains("edited relay"),
        "preview is the actual editable outgoing package")
    panel.createTask(title: "  New task  ")
    check(
        panel.snapshot.task?.title == "New task" && panel.snapshot.task?.id != task.id,
        "explicit new task creates an independent identity")
}

private func testTaskContinuation() throws {

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
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
    check(library.state.active == draft, "relay-only edits survive late completion")
    let store = HandoffResultStore(database.queue)
    let result = HandoffResult(handoffID: first.id, agent: "fixture", content: "suspected race")
    try store.insert(result)
    try library.continueTask(handoffID: first.id, resultID: result.id)
    let continued = library.state.active!
    check(
        continued.task == task && continued.id != first.draft.id,
        "continuation keeps task, creates a new draft")
    check(!continued.requestsResultReturn, "new continuation defaults return off")
    check(
        continued.relay?.text.contains("suspected race") == true,
        "only selected conclusion becomes editable relay")
    check(
        continued.relay?.text.contains("Constraints: no auto-send") == true,
        "continuation retains earlier relay constraints")
    check(continued.relay?.sourceResultID == result.id, "relay records selected source")
    check(library.state.pocket.contains(draft), "continuation parks unrelated edits")
    let retry = try library.begin(continued)
    check(
        retry.id != first.id && library.history(taskID: task.id).count == 2,
        "task spans independent attempts")
    try library.finish(retry.id, status: .failed)
    let reopened = try HopLibrary(database)
    check(
        reopened.state == library.state && reopened.tasks == [task],
        "task and relay survive restart")
    do {
        try reopened.continueTask(handoffID: retry.id, resultID: result.id)
        check(false, "a result from another attempt must be rejected")
    } catch HopLibrary.TaskError.unavailableSource {}
    check(reopened.state.active == continued, "rejected source never overwrites active input")
}
