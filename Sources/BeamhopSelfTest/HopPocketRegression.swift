import Foundation
import BeamhopCore

// Mirrors HopPocketTests under the CLT runner.
private func pocketEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T) rethrows { check(try a() == b(), "Pocket values match") }
private func pocketNotEqual<T: Equatable>(_ a: T, _ b: T) { check(a != b, "Pocket copies have independent identities") }
private func pocketTrue(_ value: Bool) { check(value, "Pocket condition is true") }
private func pocketFalse(_ value: Bool) { check(!value, "Pocket condition is false") }
private func pocketThrows<T>(_ action: @autoclosure () throws -> T) { do { _ = try action(); check(false, "Pocket operation must reject") } catch { check(true, "Pocket operation rejected") } }
private func pocketUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain: "PocketFixture", code: 1) }; return value }


struct HopPocketRegression {
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
            pocketEqual(library.state.pocket, [active])
            var edited = saved; edited.instruction = "updated"; edited.materials[0].text = "edited"
            try library.saveActive(edited); try library.hold(edited)
            try library.duplicate(edited)
            let copy = try pocketUnwrap(library.state.pocket.last)
            pocketNotEqual(copy.id, edited.id)
            pocketNotEqual(copy.materials[0].id, edited.materials[0].id)
            pocketEqual(copy.instruction, "updated")
            model.toggle(edited.id); model.toggle(copy.id)
            try model.deleteSelection()
            pocketEqual(library.state.pocket, [active])
            let reopened = try HopLibrary(db)
            try reopened.undoDeleteDrafts()
            pocketEqual(reopened.state.pocket, [active, edited, copy])
            try reopened.start(HopDraft(materials: [], route: .init(target: .clipboard)))
            pocketEqual(reopened.state.active?.materials, [])
            pocketEqual(reopened.state.pocket.count, 3)
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
            pocketEqual(model.selection, [a, b])
            pocketTrue(model.canDeliver)
            model.deliverSelection()
            let first = try pocketUnwrap(sent)
            pocketTrue(first.draft.outgoingText.contains("instruction A"))
            pocketTrue(first.draft.outgoingText.contains("instruction B"))
            pocketEqual(first.pocketSources, [a, b])
            pocketFalse(model.canDeliver)
            pocketThrows(try library.deleteDrafts([a.id]))
            try library.finish(first.id, status: .failed); done?(false)
            pocketEqual(model.selectedIDs, Set([a.id, b.id]))
            pocketEqual(library.state.pocket, [a, b])
            model.deliverSelection()
            let retry = try pocketUnwrap(sent)
            var edited = b; edited.instruction = "new edit during delivery"
            try library.hold(edited)
            try library.finish(retry.id, status: .copied); done?(true)
            pocketEqual(library.state.active, active)
            pocketEqual(library.state.pocket, [edited])
            pocketEqual(model.selectedIDs, [b.id])
            try pocketEqual(try HopLibrary(db).state, library.state)
            try library.deleteRecords([first.id])
            try pocketEqual(try HopLibrary(db).state.records.map(\.id), [retry.id])
        }
    }
    func testMixedRoutesRequireExplicitChoiceAndFilteringClearsHiddenSelection() throws {
        try fixture { library, model, _ in
            let a = HopDraft(materials: [HopMaterial(text: "alpha")], route: .init(target: .clipboard, project: "A"))
            let b = HopDraft(materials: [HopMaterial(text: "beta")], route: .init(target: .clipboard, project: "B"))
            try library.hold(a); try library.hold(b)
            model.onDeliver = { _, _ in }
            model.selectAll()
            pocketTrue(model.mixedRoutes)
            pocketFalse(model.canDeliver)
            model.chooseRoute(.init(target: .clipboard, project: "Joint review"))
            pocketTrue(model.canDeliver)
            model.blockedDraftIDs = [a.id]
            pocketFalse(model.canDeliver)
            model.blockedDraftIDs = []
            model.query = "alpha"
            pocketTrue(model.selectedIDs.isEmpty)
            model.selectAll()
            pocketEqual(model.selection, [a])
            pocketEqual(model.route, a.route)
            var attachment = b
            attachment.materials.append(HopMaterial(name: "file.pdf", path: "/fixture", image: false, bytes: 1))
            try library.hold(attachment)
            model.query = ""; model.selectAll(); model.chooseRoute(a.route)
            pocketTrue(model.hasAttachments)
            pocketFalse(model.canDeliver)
        }
    }
}
