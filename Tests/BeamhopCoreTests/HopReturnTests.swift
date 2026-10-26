import XCTest

@testable import BeamhopCore

final class HopReturnTests: XCTestCase {
    func testReturnGuardsRecoveryAndLateConsentEdit() throws {
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
        XCTAssertTrue(library.state.active == draft, "consent-only edits survive late transport completion")
        try library.recover(first)
        let retryDraft = try XCTUnwrap(library.state.active)
        let retry = try library.begin(retryDraft)
        XCTAssertTrue(
            retry.id != first.id && retry.draft.id != first.draft.id, "recovery creates a new handoff identity")
        let result = HandoffResult(handoffID: first.id, agent: "fixture", content: "late conclusion")
        try store.insert(result)
        XCTAssertTrue(try store.results(handoffID: retry.id).isEmpty, "late result stays on the first attempt")
        XCTAssertTrue(library.state.active == retryDraft, "results never consume the retry draft")
        XCTAssertTrue(library.state.records.last?.status == .preparing, "results never establish agent receipt")
        do {
            try store.insert(result)
            XCTAssertTrue(false, "duplicate result must fail")
        } catch {}
        XCTAssertTrue(try store.count() == 1, "failed insertion leaves prior results unchanged")
        let disabled = try library.begin(draft)
        for id in [disabled.id, "unknown"] {
            do {
                _ = try store.snapshot(handoffID: id)
                XCTAssertTrue(false, "unavailable handoff read must fail")
            } catch HandoffResultStore.ReturnError.unavailableHandoff {}
            do {
                try store.insert(HandoffResult(handoffID: id, agent: "fixture", content: "no"))
                XCTAssertTrue(false, "unavailable handoff write must fail")
            } catch HandoffResultStore.ReturnError.unavailableHandoff {}
        }
        do {
            try store.insert(HandoffResult(handoffID: first.id, agent: " ", content: "text"))
            XCTAssertTrue(false, "blank agent must fail")
        } catch HandoffResultStore.ReturnError.emptyAgent {}
        do {
            try store.insert(HandoffResult(handoffID: first.id, agent: "fixture", content: " \n"))
            XCTAssertTrue(false, "blank content must fail")
        } catch HandoffResultStore.ReturnError.emptyContent {}
        try library.deleteRecords([first.id])
        XCTAssertTrue(try store.count() == 0, "deleting a backup cascades its conclusions")
        do {
            try store.insert(HandoffResult(handoffID: first.id, agent: "fixture", content: "no"))
            XCTAssertTrue(false, "deleted handoff write must fail")
        } catch HandoffResultStore.ReturnError.unavailableHandoff {}
        XCTAssertTrue(library.state.active == retryDraft, "deleting an older backup preserves active input")
    }
    func testMixedBatchNeedsExplicitReturnChoiceAndKeepsInput() throws {
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
        XCTAssertFalse(mixed.acceptsResultReturn)
        try library.finish(mixed.id, status: .failed)
        let opted = try library.beginBatch([a, b], route: route, requestsResultReturn: true)
        XCTAssertTrue(opted.acceptsResultReturn)
        XCTAssertNotEqual(mixed.id, opted.id)
        let store = HandoffResultStore(db.queue)
        try store.insert(HandoffResult(handoffID: opted.id, agent: "fixture", content: "batch conclusion"))
        XCTAssertEqual(try store.results(handoffID: opted.id).count, 1)
        XCTAssertEqual(library.state.pocket, [a, b])
        try library.finish(opted.id, status: .failed)
        let model = HopPocketModel(library: library)
        model.toggle(a.id)
        model.toggle(b.id)
        XCTAssertFalse(model.requestsResultReturn)
        model.requestsResultReturn = true
        var sent: HopRecord?
        model.onDeliver = { record, _ in sent = record }
        model.deliverSelection()
        XCTAssertTrue(sent?.acceptsResultReturn == true)
    }
    func testExternalRefreshAndPaginationPreserveSelection() throws {
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
        XCTAssertTrue(model.results.isEmpty)
        let writer = try HandoffResultStore.open(path: path)
        for index in 0..<21 {
            try writer.insert(
                HandoffResult(
                    handoffID: record.id, agent: "fixture", content: "Conclusion \(index)", createdAt: Int64(index)))
        }
        model.refresh()
        XCTAssertEqual(model.results.count, 20)
        XCTAssertTrue(model.hasMore)
        model.selectedID = model.results.last?.id
        let selection = model.selectedID
        XCTAssertEqual(model.selectedRecord?.id, record.id)
        try writer.insert(
            HandoffResult(handoffID: record.id, agent: "another-agent", content: "Late conclusion", createdAt: 100))
        model.refresh()
        XCTAssertEqual(model.selectedID, selection)
        model.loadMore()
        XCTAssertEqual(model.results.count, 22)
        XCTAssertFalse(model.hasMore)
        try library.finish(record.id, status: .failed)
        try library.deleteRecords([record.id])
        model.refresh()
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.selectedRecord)
        XCTAssertNil(model.selectedID)
    }
    func testConsentSurvivesPanelRestoreAndLegacyDraftsStayDisabled() throws {
        let source = Capture(
            source: .ax, appBundleID: "fixture", appName: "Fixture", selectedText: "source", pid: 1,
            captureMethod: "fixture")
        let panel = CapturePanelModel(capture: source, initialTarget: .clipboard, onConfirm: { _, _ in }, onCancel: {})
        XCTAssertFalse(panel.requestsResultReturn)
        panel.requestsResultReturn = true
        let draft = panel.snapshot
        XCTAssertTrue(draft.requestsResultReturn)
        panel.requestsResultReturn = false
        panel.restore(draft)
        XCTAssertTrue(panel.requestsResultReturn)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as! [String: Any]
        legacy.removeValue(forKey: "requestsResultReturn")
        let old = try JSONDecoder().decode(HopDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertFalse(old.requestsResultReturn)
        var oldRecord =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(HopRecord(draft: old))) as! [String: Any]
        oldRecord.removeValue(forKey: "envelopeVersion")
        let decoded = try JSONDecoder().decode(HopRecord.self, from: JSONSerialization.data(withJSONObject: oldRecord))
        XCTAssertEqual(decoded.outgoingText, old.outgoingText)
        XCTAssertFalse(decoded.acceptsResultReturn)
    }
    func testExternalConclusionKeepsFrozenAttemptAndNewerInputAcrossRestart() throws {
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
        XCTAssertEqual(snapshot.text, record.textFallback)
        XCTAssertEqual(snapshot.transportStatus, .copied)
        let result = HandoffResult(handoffID: record.id, agent: "fixture-agent", content: "结论 <>&", createdAt: 10)
        try writer.insert(result)
        XCTAssertEqual(try writer.results(handoffID: record.id), [result])
        XCTAssertEqual(try HandoffResultStore.open(path: path).results(handoffID: record.id), [result])
        let reopened = try HopLibrary(db)
        XCTAssertEqual(reopened.state.active, newer)
        XCTAssertEqual(reopened.state.records.first?.draft, draft)
        XCTAssertEqual(reopened.state.records.first?.status, .copied)
    }
    func testHandoffIdentityKeepsEditedPayloadLiteralAndReturnOptional() throws {
        let source = Capture(
            source: .ax, appBundleID: "test.source", appName: "Browser",
            selectedText: "private original", pid: 1, captureMethod: "fixture")
        var material = HopMaterial(capture: source)
        material.text = "edited <>&"
        var draft = HopDraft(
            materials: [material], instruction: "/review\nkeep literal",
            route: .init(target: .claudeCode))
        let record = HopRecord(draft: draft)
        XCTAssertTrue(record.outgoingText.hasPrefix("/review\nkeep literal\n\nSource: Browser\nedited <>&"))
        XCTAssertTrue(record.outgoingText.contains("Handoff ID: \(record.id)"))
        XCTAssertFalse(record.outgoingText.contains("private original"))
        XCTAssertFalse(record.outgoingText.contains("save_handoff_result"))
        draft.requestsResultReturn = true
        let enabled = HopRecord(draft: draft)
        XCTAssertTrue(enabled.outgoingText.contains("save_handoff_result"))
        XCTAssertTrue(enabled.outgoingText.contains(enabled.id))
        XCTAssertNotEqual(enabled.id, record.id)
        XCTAssertEqual(enabled.status, .preparing)
    }
}
