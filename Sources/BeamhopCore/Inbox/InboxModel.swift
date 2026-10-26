import Foundation
import Combine

/// Inbox state is independent of AppKit so selection and external MCP writes can be tested
/// against a temporary DB. The window owns refresh scheduling; callers use the main thread.
public final class InboxModel: ObservableObject {
    public let handoffConclusions = HandoffResultsModel()
    @Published public private(set) var captures: [Capture] = []
    @Published public private(set) var deliveries: [String: [Delivery]] = [:]
    @Published public private(set) var resultCounts: [String: Int] = [:]
    @Published public private(set) var selectedResults: [CaptureResult] = []
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var detailErrorMessage: String?
    @Published public var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            resultLimit = 100
            if let id = selectedID {
                events?.record(name: EventStore.Name.captureViewed, captureID: id)
            }
            refreshSelectedDetails()
        }
    }
    @Published public var searchQuery = ""

    public var selected: Capture? { captures.first { $0.id == selectedID } }
    public var hasMoreResults: Bool {
        guard let selectedID else { return false }
        return selectedResults.count < (resultCounts[selectedID] ?? 0)
    }

    private var store: CaptureStore?
    private var events: EventStore?
    private var onDeliver: ((Capture, DeliveryTarget) -> Void)?
    private var resultLimit = 100

    public init() {}

    public func configure(store: CaptureStore, events: EventStore?, handoffs: HandoffResultStore? = nil,
                          onDeliver: @escaping (Capture, DeliveryTarget) -> Void) {
        self.store = store
        self.events = events
        self.onDeliver = onDeliver
        if let handoffs { handoffConclusions.configure(store: handoffs) }
    }

    public func logOpened() { events?.record(name: EventStore.Name.inboxOpened) }

    public func reload() {
        guard let store else { return }
        do {
            let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let rows = query.isEmpty ? try store.recent(limit: 200) : try store.search(query)
            let counts = try store.resultCounts(captureIDs: rows.map(\.id))
            captures = rows
            resultCounts = counts
            if selectedID != nil, !rows.contains(where: { $0.id == selectedID }) { selectedID = nil }
            // Only the list's status summary is bounded. Selecting row 51+ still fetches its
            // complete detail, even when it was outside this summary prefetch.
            var summaries: [String: [Delivery]] = [:]
            for capture in rows.prefix(50) {
                summaries[capture.id] = try store.deliveries(captureID: capture.id)
            }
            deliveries = summaries
            refreshSelectedDetails()
            errorMessage = nil
        } catch {
            errorMessage = L10n.s("Could not refresh Inbox. Try Refresh again.")
        }
    }

    public func runSearch() {
        reload()
        events?.record(name: EventStore.Name.inboxSearch, detail: "hits=\(captures.count)")
    }

    /// Re-query rather than relying on in-process notifications: MCP writes in another process.
    /// This must not log a new visit/search/view every two seconds.
    public func refreshSelectedDetails() {
        handoffConclusions.refresh()
        guard let store, let id = selected?.id else {
            selectedResults = []
            detailErrorMessage = nil
            return
        }
        do {
            let results = try store.results(captureID: id, limit: resultLimit)
            let history = try store.deliveries(captureID: id)
            let counts = try store.resultCounts(captureIDs: [id])
            selectedResults = results
            deliveries[id] = history
            resultCounts[id] = counts[id] ?? 0
            detailErrorMessage = nil
        } catch {
            selectedResults = []
            detailErrorMessage = L10n.s("Could not load agent conclusions. Try Refresh again.")
        }
    }

    public func loadMoreResults() {
        resultLimit += 100
        refreshSelectedDetails()
    }

    public func deliver(_ capture: Capture, to target: DeliveryTarget) {
        events?.record(name: EventStore.Name.inboxRedeliver,
                       detail: "target=\(target.rawValue)", captureID: capture.id)
        onDeliver?(capture, target)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.refreshSelectedDetails() }
    }

    public func softDelete(_ capture: Capture) {
        guard let store else { return }
        do {
            try store.softDelete(id: capture.id)
            events?.record(name: EventStore.Name.captureSoftDeleted, captureID: capture.id)
            if selectedID == capture.id { selectedID = nil }
            reload()
        } catch {
            errorMessage = L10n.s("Could not delete capture. Try again.")
        }
    }
}
