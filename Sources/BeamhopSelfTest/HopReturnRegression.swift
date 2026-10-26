import BeamhopCore
import Foundation

func runHopReturnRegression() throws {
    print("== Hop identity and optional return ==")
    let source = Capture(
        source: .ax, appBundleID: "test.source", appName: "Browser",
        selectedText: "private original", pid: 1, captureMethod: "fixture")
    var material = HopMaterial(capture: source)
    material.text = "edited <>&"
    var draft = HopDraft(
        materials: [material], instruction: "/review\nkeep literal",
        route: .init(target: .claudeCode))
    let record = HopRecord(draft: draft)
    check(
        record.outgoingText.hasPrefix("/review\nkeep literal\n\nSource: Browser\nedited <>&"),
        "literal instruction and edited payload stay first")
    check(record.outgoingText.contains("Handoff ID: \(record.id)"), "identity travels with the handoff")
    check(!record.outgoingText.contains("private original"), "original is not silently exported")
    check(!record.outgoingText.contains("save_handoff_result"), "return defaults off")
    draft.requestsResultReturn = true
    let enabled = HopRecord(draft: draft)
    check(enabled.outgoingText.contains("save_handoff_result"), "opt-in advertises optional return tool")
    check(enabled.outgoingText.contains(enabled.id) && enabled.id != record.id, "each attempt has its own identity")
    check(enabled.status == .preparing, "requesting a conclusion is not completion")
    try testExternalHandoffConclusion()
    try testHandoffConsent()
    try testHandoffResultsRefresh()
    try testHandoffBatchConsent()
    try testHandoffReturnGuards()
    try testExistingOnlyWriter()
}

private func testExistingOnlyWriter() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let missing = directory.appendingPathComponent("missing.sqlite")
    do {
        _ = try Database.openExistingReadWrite(path: missing)
        check(false, "existing-only opener rejects a missing file")
    } catch {}
    check(!FileManager.default.fileExists(atPath: missing.path), "SQLite does not create a missing Inbox")
    let path = directory.appendingPathComponent("space # ? % 数据.sqlite")
    let db = try Database(path: path)
    let source = Capture(
        source: .ax, appBundleID: "fixture", appName: "Fixture", selectedText: "capture", pid: 1,
        captureMethod: "fixture")
    try CaptureStore(db).insert(source)
    let library = try HopLibrary(db)
    let record = try library.begin(HopDraft(materials: [HopMaterial(text: "edited")], requestsResultReturn: true))
    let store = try HandoffResultStore.open(path: path)
    try store.insert(HandoffResult(handoffID: record.id, agent: "fixture", content: "kept"))
    check(try store.count() == 1, "percent-encoded existing paths remain writable")
    let legacy = try ResultStore.open(path: path)
    try legacy.insert(CaptureResult(originCaptureID: source.id, agent: "fixture", content: "legacy kept"))
    let moved = directory.appendingPathComponent("moved.sqlite")
    try FileManager.default.moveItem(at: path, to: moved)
    // Exercise the SQLite open itself after disappearance, not a cached fileExists result.
    do {
        _ = try Database.openExistingReadWrite(path: path)
        check(false, "removed file must not reopen")
    } catch {}
    do {
        _ = try HandoffResultStore.open(path: path)
        check(false, "removed handoff store must not reopen")
    } catch {}
    do {
        _ = try ResultStore.open(path: path)
        check(false, "removed legacy store must not reopen")
    } catch {}
    check(!FileManager.default.fileExists(atPath: path.path), "writers do not recreate an Inbox moved by the app")
    check(FileManager.default.fileExists(atPath: moved.path), "original database stays preserved")
}

private func testHandoffReturnGuards() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("test.sqlite")
    let db = try Database(path: path)
    let library = try HopLibrary(db)
    let store = HandoffResultStore(db.queue)
    var draft = HopDraft(materials: [HopMaterial(text: "only edited input")], requestsResultReturn: true)
    try library.start(draft)
    let first = try library.begin(draft)
    // A consent-only edit is still a new snapshot and must survive a late copy.
    draft.requestsResultReturn = false
    try library.saveActive(draft)
    try library.finish(first.id, status: .copied)
    check(library.state.active == draft, "consent-only edits survive late transport completion")
    try library.recover(first)
    guard let retryDraft = library.state.active else { throw HandoffResultStore.ReturnError.unavailableHandoff }
    let retry = try library.begin(retryDraft)
    check(retry.id != first.id && retry.draft.id != first.draft.id, "recovery creates a new handoff identity")
    let result = HandoffResult(handoffID: first.id, agent: "fixture", content: "late conclusion")
    try store.insert(result)
    check(try store.results(handoffID: retry.id).isEmpty, "late result stays on the first attempt")
    check(library.state.active == retryDraft, "results never consume the retry draft")
    check(library.state.records.last?.status == .preparing, "results never establish agent receipt")
    do {
        try store.insert(result)
        check(false, "duplicate result must fail")
    } catch {}
    check(try store.count() == 1, "failed insertion leaves prior results unchanged")
    let disabled = try library.begin(draft)
    for id in [disabled.id, "unknown"] {
        do {
            _ = try store.snapshot(handoffID: id)
            check(false, "unavailable handoff read must fail")
        } catch HandoffResultStore.ReturnError.unavailableHandoff {}
        do {
            try store.insert(HandoffResult(handoffID: id, agent: "fixture", content: "no"))
            check(false, "unavailable handoff write must fail")
        } catch HandoffResultStore.ReturnError.unavailableHandoff {}
    }
    do {
        try store.insert(HandoffResult(handoffID: first.id, agent: " ", content: "text"))
        check(false, "blank agent must fail")
    } catch HandoffResultStore.ReturnError.emptyAgent {}
    do {
        try store.insert(HandoffResult(handoffID: first.id, agent: "fixture", content: " \n"))
        check(false, "blank content must fail")
    } catch HandoffResultStore.ReturnError.emptyContent {}
    try library.deleteRecords([first.id])
    check(try store.count() == 0, "deleting a backup cascades its conclusions")
    do {
        try store.insert(HandoffResult(handoffID: first.id, agent: "fixture", content: "no"))
        check(false, "deleted handoff write must fail")
    } catch HandoffResultStore.ReturnError.unavailableHandoff {}
    check(library.state.active == retryDraft, "deleting an older backup preserves active input")
}

private func testHandoffBatchConsent() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let db = try Database(path: directory.appendingPathComponent("test.sqlite"))
    let library = try HopLibrary(db)
    let route = HopRoute(target: .clipboard)
    let a = HopDraft(materials: [HopMaterial(text: "one")], route: route, requestsResultReturn: true)
    let b = HopDraft(materials: [HopMaterial(text: "two")], route: route)
    try library.hold(a)
    try library.hold(b)
    let mixed = try library.beginBatch([a, b], route: route)
    check(!(mixed.acceptsResultReturn), "mixed consent defaults disabled")
    try library.finish(mixed.id, status: .failed)
    let opted = try library.beginBatch([a, b], route: route, requestsResultReturn: true)
    check(opted.acceptsResultReturn, "explicit batch choice enables return")
    check(mixed.id != opted.id, "batch attempts have independent identities")
    let store = HandoffResultStore(db.queue)
    try store.insert(HandoffResult(handoffID: opted.id, agent: "fixture", content: "batch conclusion"))
    check(try store.results(handoffID: opted.id).count == 1, "batch conclusions preserve source drafts")
    check(library.state.pocket == [a, b], "batch conclusions preserve source drafts")
    try library.finish(opted.id, status: .failed)
    let model = HopPocketModel(library: library)
    model.toggle(a.id)
    model.toggle(b.id)
    check(!(model.requestsResultReturn), "mixed consent defaults disabled")
    model.requestsResultReturn = true
    var sent: HopRecord?
    model.onDeliver = { record, _ in sent = record }
    model.deliverSelection()
    check(sent?.acceptsResultReturn == true, "explicit batch choice enables return")
}

private func testHandoffResultsRefresh() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("test.sqlite")
    let db = try Database(path: path)
    let library = try HopLibrary(db)
    let record = try library.begin(
        HopDraft(materials: [HopMaterial(text: "text-only snapshot")], requestsResultReturn: true))
    let model = HandoffResultsModel()
    model.configure(store: HandoffResultStore(db.queue))
    check(model.results.isEmpty, "result presentation reflects external writes and deletions")
    let writer = try HandoffResultStore.open(path: path)
    for index in 0..<21 {
        try writer.insert(
            HandoffResult(
                handoffID: record.id, agent: "fixture", content: "Conclusion \(index)", createdAt: Int64(index)))
    }
    model.refresh()
    check(model.results.count == 20, "external refresh and pagination preserve result selection")
    check(model.hasMore, "result presentation reflects external writes and deletions")
    model.selectedID = model.results.last?.id
    let selection = model.selectedID
    check(model.selectedRecord?.id == record.id, "external refresh and pagination preserve result selection")
    try writer.insert(
        HandoffResult(handoffID: record.id, agent: "another-agent", content: "Late conclusion", createdAt: 100))
    model.refresh()
    check(model.selectedID == selection, "external refresh and pagination preserve result selection")
    model.loadMore()
    check(model.results.count == 22, "external refresh and pagination preserve result selection")
    check(!(model.hasMore), "all results loaded")
    try library.finish(record.id, status: .failed)
    try library.deleteRecords([record.id])
    model.refresh()
    check(model.results.isEmpty, "result presentation reflects external writes and deletions")
    check(model.selectedRecord == nil, "deleted handoff clears result selection")
    check(model.selectedID == nil, "deleted handoff clears result selection")
}

private func testHandoffConsent() throws {
    let source = Capture(
        source: .ax, appBundleID: "fixture", appName: "Fixture", selectedText: "source", pid: 1,
        captureMethod: "fixture")
    let panel = CapturePanelModel(capture: source, initialTarget: .clipboard, onConfirm: { _, _ in }, onCancel: {})
    check(!(panel.requestsResultReturn), "return is disabled unless opted in")
    panel.requestsResultReturn = true
    let draft = panel.snapshot
    check(draft.requestsResultReturn, "explicit return choice survives snapshot and restore")
    panel.requestsResultReturn = false
    panel.restore(draft)
    check(panel.requestsResultReturn, "explicit return choice survives snapshot and restore")
    var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
    legacy.removeValue(forKey: "requestsResultReturn")
    let old = try JSONDecoder().decode(HopDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
    check(!(old.requestsResultReturn), "return is disabled unless opted in")
    var oldRecord =
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(HopRecord(draft: old))) as! [String: Any]
    oldRecord.removeValue(forKey: "envelopeVersion")
    let decoded = try JSONDecoder().decode(HopRecord.self, from: JSONSerialization.data(withJSONObject: oldRecord))
    check(decoded.outgoingText == old.outgoingText, "legacy handoff output stays unchanged")
    check(!(decoded.acceptsResultReturn), "return is disabled unless opted in")
}

private func testExternalHandoffConclusion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("test.sqlite")
    let db = try Database(path: path)
    let library = try HopLibrary(db)
    let draft = HopDraft(
        materials: [HopMaterial(text: "edited snapshot")],
        route: .init(target: .clipboard), requestsResultReturn: true)
    try library.start(draft)
    let record = try library.begin(draft)
    var newer = draft
    newer.materials[0].text = "newer input"
    try library.saveActive(newer)
    try library.finish(record.id, status: .copied)
    let writer = try HandoffResultStore.open(path: path)
    let snapshot = try writer.snapshot(handoffID: record.id)
    check(snapshot.text == record.textFallback, "frozen result association survives external write and restart")
    check(snapshot.transportStatus == .copied, "frozen result association survives external write and restart")
    let result = HandoffResult(handoffID: record.id, agent: "fixture-agent", content: "结论 <>&", createdAt: 10)
    try writer.insert(result)
    check(
        try writer.results(handoffID: record.id) == [result],
        "frozen result association survives external write and restart")
    check(
        try HandoffResultStore.open(path: path).results(handoffID: record.id) == [result],
        "frozen result association survives external write and restart")
    let reopened = try HopLibrary(db)
    check(reopened.state.active == newer, "frozen result association survives external write and restart")
    check(reopened.state.records.first?.draft == draft, "frozen result association survives external write and restart")
    check(
        reopened.state.records.first?.status == .copied, "frozen result association survives external write and restart"
    )
}
