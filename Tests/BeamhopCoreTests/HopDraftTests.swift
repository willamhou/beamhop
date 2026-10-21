import XCTest
@testable import BeamhopCore

final class HopDraftTests: XCTestCase {
    func testEditedTextAndLiteralInstructionAreTheOnlyOutgoingCopy() throws {
        let capture = Capture(source: .ax, appBundleID: "com.example", appName: "Mail",
                              url: "https://example.com/source", selectedText: "immutable secret original",
                              extractedBody: "unselected page", pid: 1, captureMethod: "ax")
        let model = CapturePanelModel(capture: capture, initialTarget: .chatgptDesktop,
                                      onConfirm: { _, _ in XCTFail("Unsupported attachment must block") }, onCancel: {})
        model.materials[0].text = "edited <>&"
        model.additionalText = "an independent addition"
        model.note = "/review\nKeep this exact"
        let draft = model.snapshot
        XCTAssertEqual(draft.materials.count, 2)
        XCTAssertEqual(draft.materials[0].original, capture)
        XCTAssertEqual(draft.materials[0].originalText, "immutable secret original")
        XCTAssertTrue(draft.outgoingText.hasPrefix(model.note))
        XCTAssertTrue(draft.outgoingText.contains("edited <>&"))
        XCTAssertFalse(draft.outgoingText.contains("immutable secret original"))
        XCTAssertFalse(draft.outgoingText.contains("unselected page"))
        let handoff = Handoff(items: [.init(capture: capture)], editedText: draft.outgoingText)
        XCTAssertEqual(handoff.markdown, draft.outgoingText)
        XCTAssertEqual(handoff.claudeTrigger, draft.outgoingText)
        model.materials.append(HopMaterial(name: "image.png", path: "/local/image.png", image: true, bytes: 10))
        XCTAssertFalse(model.canConfirm)
        model.confirm()
        XCTAssertTrue(model.snapshot.textFallback.contains("image.png"))
        let saved = model.snapshot
        model.chooseRoute(.init(target: .kimiWork, project: "Other project", session: .newInApp))
        XCTAssertEqual(model.snapshot.materials, saved.materials)
        XCTAssertEqual(model.note, saved.instruction)
        model.usesProjectContext = true
        model.chooseTool(.clipboard)
        XCTAssertEqual(model.workName, "Other project")
        XCTAssertEqual(model.session, .currentWindow)
        model.chooseTool(nil)
        XCTAssertEqual(model.confirmLabel, "Save local draft")
    }

    func testPocketRestoreCopyRecoveryAndLateCompletionAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let db = try Database(path: directory.appendingPathComponent("test.sqlite"))
        let library = try HopLibrary(db)
        let first = HopDraft(materials: [HopMaterial(text: "first")], instruction: "prompt A",
                             route: .init(target: .clipboard, project: "A"))
        let second = HopDraft(materials: [HopMaterial(text: "second")],
                              route: .init(target: .kimiWork, project: "B", session: .newInApp))
        try library.start(first); try library.hold(first); try library.start(second)
        try library.restore(first.id)
        XCTAssertEqual(library.state.active, first)
        XCTAssertEqual(library.state.pocket, [second])
        try library.addMaterials(from: second)
        XCTAssertEqual(library.state.active?.route, first.route)
        XCTAssertEqual(library.state.active?.instruction, first.instruction)
        XCTAssertEqual(library.state.pocket, [second])
        XCTAssertNotEqual(library.state.active?.materials.last?.id, second.materials.first?.id)
        let before = library.state.active!
        let record = try library.begin(before)
        var newer = before; newer.materials[0].text = "newer edit"
        try library.saveActive(newer)
        try library.finish(record.id, status: .prepared)
        XCTAssertEqual(library.state.active, newer)
        XCTAssertEqual(library.state.records.first?.draft, before)
        try library.recover(library.state.records[0])
        XCTAssertTrue(library.state.pocket.contains(newer))
        XCTAssertEqual(library.state.active?.materials, before.materials)
        try library.remember(first.route); try library.remember(second.route)
        let anotherApp = HopRoute(target: .chatgptDesktop, project: "A")
        try library.remember(anotherApp)
        XCTAssertEqual(library.state.routes.count, 3)
        let reopened = try HopLibrary(db)
        XCTAssertEqual(reopened.state, library.state)
        let pending = try reopened.begin(reopened.state.active!)
        let interrupted = try HopLibrary(db)
        XCTAssertEqual(interrupted.state.records.first { $0.id == pending.id }?.status, .failed)
        XCTAssertTrue(interrupted.state.records.last?.detail?.contains("unknown") == true)
    }
}
