import Foundation
import Combine

/// The shelf's selection is independent of history, filtering and the active editor.
public final class HopPocketModel: ObservableObject {
    public enum Section: Hashable { case drafts, history }
    public let library: HopLibrary
    @Published public var section: Section = .drafts
    /// SwiftUI's search-field binding writes the unchanged value back on view updates
    /// (observed on macOS 15.7: writeback fires during delivery state changes); only a
    /// real query edit may clear the selection, or a failed handoff loses it silently.
    @Published public var query = "" { didSet { guard oldValue != query else { return }; selectedIDs = []; route = nil } }
    @Published public private(set) var selectedIDs: Set<String> = []
    @Published public private(set) var route: HopRoute?
    @Published public private(set) var isDelivering = false
    @Published public var error: String?
    @Published public var blockedDraftIDs: Set<String> = []
    @Published public var historyLimit = 20
    @Published public var availableTargets = DeliveryTarget.allCases
    public var onDeliver: ((HopRecord, @escaping (Bool) -> Void) -> Void)?
    private var subscription: AnyCancellable?

    public init(library: HopLibrary) {
        self.library = library
        subscription = library.$state.dropFirst().sink { [weak self] state in
            guard let self else { return }
            self.selectedIDs.formIntersection(Set(state.pocket.map(\.id)))
            self.objectWillChange.send()
        }
    }
    public var selection: [HopDraft] { library.state.pocket.filter { selectedIDs.contains($0.id) } }
    private func matches(_ draft: HopDraft) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || ([draft.instruction, draft.route.project, draft.route.target?.displayName ?? ""]
            + draft.materials.map { $0.text + " " + $0.name }).contains { $0.localizedCaseInsensitiveContains(term) }
    }
    public var drafts: [HopDraft] { library.state.pocket.filter(matches) }
    public var records: [HopRecord] { library.state.records.reversed().filter { matches($0.draft) } }
    public var mixedRoutes: Bool { guard let first = selection.first else { return false }; return selection.contains { $0.route != first.route } }
    public var hasAttachments: Bool { selection.contains { !$0.attachments.isEmpty } }
    public var blockedSelection: Bool { !selectedIDs.isDisjoint(with: blockedDraftIDs.union(library.inFlightIDs)) }
    public var canDeliver: Bool {
        !isDelivering && !selection.isEmpty && !blockedSelection && !hasAttachments
            && route?.target.map { availableTargets.contains($0) } == true && onDeliver != nil
    }
    public func toggle(_ id: String) {
        guard !isDelivering else { return }
        let previous = selection.map(\.route)
        let chosen = route
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        inferRoute()
        let current = selection.map(\.route)
        if !current.isEmpty, previous.allSatisfy(current.contains), current.allSatisfy(previous.contains) { route = chosen }
    }
    public func selectAll() {
        guard !isDelivering else { return }
        let ids = Set(drafts.map(\.id))
        selectedIDs = selectedIDs == ids ? [] : ids
        inferRoute()
    }
    private func inferRoute() {
        route = mixedRoutes ? nil : selection.first?.route
        error = nil
    }
    public func chooseRoute(_ route: HopRoute) { self.route = route }
    public func deleteSelection() throws {
        guard !isDelivering, !blockedSelection else { throw HopLibrary.PocketError.changed }
        try library.deleteDrafts(selectedIDs)
        selectedIDs = []; route = nil
    }
    public func deliverSelection() {
        guard canDeliver, let route, let onDeliver else { return }
        do {
            let record = try library.beginBatch(selection, route: route)
            isDelivering = true; error = nil
            onDeliver(record) { [weak self] succeeded in
                guard let self else { return }
                self.isDelivering = false
                if succeeded { self.selectedIDs.formIntersection(Set(self.library.state.pocket.map(\.id))) }
                else { self.error = L10n.s("Handoff failed. Your selection is still here.") }
            }
        } catch { self.error = error.localizedDescription }
    }
}
