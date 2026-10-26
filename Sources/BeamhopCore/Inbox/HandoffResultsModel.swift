import Foundation
import Combine

/// Shared result presentation for Inbox and a scoped Pocket history entry. Refresh
/// through the store because the MCP writer lives in another process. Main-thread callers.
public final class HandoffResultsModel: ObservableObject {
    @Published public private(set) var results: [HandoffResult] = []
    @Published public private(set) var total = 0
    @Published public private(set) var selectedRecord: HopRecord?
    @Published public private(set) var error: String?
    @Published public var selectedID: String? { didSet { loadSelectedRecord() } }
    public var selectedResult: HandoffResult? { results.first { $0.id == selectedID } }
    public var hasMore: Bool { results.count < total }
    private var handoffID: String?
    private var limit = 20
    private var store: HandoffResultStore?
    public init() {}
    public func configure(store: HandoffResultStore) { self.store = store; refresh() }
    public func showHandoff(_ id: String?) {
        guard id != handoffID else { refresh(); return }
        handoffID = id; limit = 20; selectedID = nil
        refresh()
    }
    public func refresh() {
        guard let store else { return }
        do {
            var rows = try store.results(handoffID: handoffID, limit: limit)
            let count = try store.count(handoffID: handoffID)
            // A newer write can push the selected row past the page boundary. Keep
            // that real row visible, but never resurrect a deleted or differently scoped row.
            if let selectedID, !rows.contains(where: { $0.id == selectedID }),
               let selected = try store.result(id: selectedID),
               handoffID == nil || selected.handoffID == handoffID {
                rows.append(selected)
            }
            results = rows; total = count
            if let selectedID, !rows.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            try refreshSelectedRecord()
            error = nil
        } catch {
            results = []; total = 0; selectedRecord = nil
            self.error = L10n.s("Could not load handoff conclusions. Try Refresh again.")
        }
    }
    public func loadMore() { limit += 20; refresh() }
    private func refreshSelectedRecord() throws {
        selectedRecord = try selectedResult.flatMap { try store?.recordForDisplay(handoffID: $0.handoffID) }
    }
    private func loadSelectedRecord() {
        do { try refreshSelectedRecord() }
        catch {
            selectedRecord = nil
            self.error = L10n.s("Could not load handoff conclusions. Try Refresh again.")
        }
    }
}
