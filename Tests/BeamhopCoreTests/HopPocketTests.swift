import XCTest
@testable import BeamhopCore

final class HopPocketTests: XCTestCase {
    private func fixture(_ body: (HopLibrary, HopPocketModel, Database) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(path: dir.appendingPathComponent("test.sqlite"))
        let library = try HopLibrary(db)
        try body(library, HopPocketModel(library: library), db)
    }
    func testCreateEditDuplicateDeleteUndoSurviveRestart() throws {
        try fixture { library, model, db in
            let active = HopDraft(materials: [HopMaterial(text: "current")])
            let saved = HopDraft(materials: [HopMaterial(text: "saved")], instruction: "review")
            try library.start(active); try library.hold(saved)
            try library.restore(saved.id)
            XCTAssertEqual(library.state.pocket, [active])
            var edited = saved; edited.instruction = "updated"; edited.materials[0].text = "edited"
            try library.saveActive(edited); try library.hold(edited)
            try library.duplicate(edited)
            let copy = try XCTUnwrap(library.state.pocket.last)
            XCTAssertNotEqual(copy.id, edited.id)
            XCTAssertNotEqual(copy.materials[0].id, edited.materials[0].id)
            XCTAssertEqual(copy.instruction, "updated")
            model.toggle(active.id); model.toggle(copy.id)
            try model.deleteSelection()
            XCTAssertEqual(library.state.pocket, [edited])
            let reopened = try HopLibrary(db)
            try reopened.undoDeleteDrafts()
            XCTAssertEqual(reopened.state.pocket, [active, edited, copy])
            try reopened.start(HopDraft(materials: [], route: .init(target: .clipboard)))
            XCTAssertEqual(reopened.state.active?.materials, [])
            XCTAssertEqual(reopened.state.pocket.count, 3)
        }
    }
    func testBatchFailureRetryAndLateEditPreservation() throws {
        try fixture { library, model, db in
            let route = HopRoute(target: .clipboard, project: "A")
            let a = HopDraft(materials: [HopMaterial(text: "evidence A")], instruction: "instruction A", route: route)
            let b = HopDraft(materials: [HopMaterial(text: "evidence B")], instruction: "instruction B", route: route)
            let active = HopDraft(materials: [HopMaterial(text: "untouched active")])
            try library.start(active); try library.hold(a); try library.hold(b)
            var sent: HopRecord?
            var done: ((Bool) -> Void)?
            model.onDeliver = { sent = $0; done = $1 }
            model.toggle(b.id); model.toggle(a.id)
            XCTAssertEqual(model.selection, [a, b])
            XCTAssertTrue(model.canDeliver)
            model.deliverSelection()
            let first = try XCTUnwrap(sent)
            XCTAssertTrue(first.draft.outgoingText.contains("instruction A"))
            XCTAssertTrue(first.draft.outgoingText.contains("instruction B"))
            XCTAssertEqual(first.pocketSources, [a, b])
            XCTAssertFalse(model.canDeliver)
            XCTAssertThrowsError(try library.deleteDrafts([a.id]))
            try library.finish(first.id, status: .failed); done?(false)
            XCTAssertEqual(model.selectedIDs, Set([a.id, b.id]))
            XCTAssertEqual(library.state.pocket, [a, b])
            model.deliverSelection()
            let retry = try XCTUnwrap(sent)
            var edited = b; edited.instruction = "new edit during delivery"
            try library.hold(edited)
            try library.finish(retry.id, status: .copied); done?(true)
            XCTAssertEqual(library.state.active, active)
            XCTAssertEqual(library.state.pocket, [edited])
            XCTAssertEqual(model.selectedIDs, [b.id])
            XCTAssertEqual(try HopLibrary(db).state, library.state)
            try library.deleteRecords([first.id])
            XCTAssertEqual(try HopLibrary(db).state.records.map(\.id), [retry.id])
        }
    }
    func testMixedRoutesRequireExplicitChoiceAndFilteringClearsHiddenSelection() throws {
        try fixture { library, model, _ in
            let a = HopDraft(materials: [HopMaterial(text: "alpha")], route: .init(target: .clipboard, project: "A"))
            let b = HopDraft(materials: [HopMaterial(text: "beta")], route: .init(target: .clipboard, project: "B"))
            try library.hold(a); try library.hold(b)
            model.onDeliver = { _, _ in }
            model.selectAll()
            XCTAssertTrue(model.mixedRoutes)
            XCTAssertFalse(model.canDeliver)
            model.chooseRoute(.init(target: .clipboard, project: "Joint review"))
            XCTAssertTrue(model.canDeliver)
            model.blockedDraftIDs = [a.id]
            XCTAssertFalse(model.canDeliver)
            model.blockedDraftIDs = []
            model.query = "alpha"
            XCTAssertTrue(model.selectedIDs.isEmpty)
            model.selectAll()
            XCTAssertEqual(model.selection, [a])
            XCTAssertEqual(model.route, a.route)
            var attachment = b
            attachment.materials.append(HopMaterial(name: "file.pdf", path: "/fixture", image: false, bytes: 1))
            try library.hold(attachment)
            model.query = ""; model.selectAll(); model.chooseRoute(a.route)
            XCTAssertTrue(model.hasAttachments)
            XCTAssertFalse(model.canDeliver)
        }
    }
}
