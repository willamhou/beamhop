import Foundation
import Combine

/// Selection and recovery live outside AppKit so a failed handoff can be tested.
public final class PocketModel: ObservableObject {
    public typealias Pair = (PocketItem, Capture)
    @Published public private(set) var items: [Pair] = []
    @Published public private(set) var selectedIDs: Set<String> = []
    @Published public var selectedTarget: DeliveryTarget? = nil
    @Published public private(set) var isDelivering = false
    @Published public private(set) var error: String?
    private var store: PocketStore?
    private var onDeliver: (([Pair], DeliveryTarget, @escaping (Bool) -> Void) -> Void)?
    private var onCountChange: ((Int) -> Void)?

    public init() {}

    public func configure(store: PocketStore,
                          onDeliver: @escaping ([Pair], DeliveryTarget, @escaping (Bool) -> Void) -> Void,
                          onCountChange: ((Int) -> Void)? = nil) {
        self.store = store
        self.onDeliver = onDeliver
        self.onCountChange = onCountChange
    }

    public func reload() {
        do {
            items = try store?.liveStack() ?? []
            selectedIDs.formIntersection(Set(items.map { $0.0.id }))
            onCountChange?(items.count)
        } catch {
            self.error = L10n.s("Could not load held materials. Try again.")
        }
    }

    public var count: Int { items.count }
    public var selection: [Pair] { items.filter { selectedIDs.contains($0.0.id) } }

    public func toggle(_ id: String) {
        guard !isDelivering else { return }
        let previousIntent = Set(selection.map(Self.intent))
        let previousTarget = selectedTarget
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        error = nil
        // Keep an explicit choice while adding/removing materials for the same work.
        // Clear it only when crossing into a different original destination.
        if !selectedIDs.isEmpty, Set(selection.map(Self.intent)) == previousIntent {
            selectedTarget = previousTarget
            return
        }
        let targets = Set(selection.compactMap { $0.0.intendedTarget })
        selectedTarget = targets.count == 1 ? targets.first : nil
    }

    /// A different named work must not ride along just because it uses the same app.
    public var hasMixedDestinations: Bool {
        Set(selection.map(Self.intent)).count > 1
    }

    private static func intent(_ pair: Pair) -> String {
        (pair.0.workName?.lowercased() ?? "") + "\u{0}" + (pair.0.intendedTarget?.rawValue ?? "")
    }

    public var canDeliver: Bool {
        !isDelivering && !selection.isEmpty && !hasMixedDestinations && selectedTarget != nil
    }

    public func remove(_ id: String) {
        guard !isDelivering else { return }
        do { try store?.remove(id: id); reload() }
        catch { self.error = L10n.s("Could not remove this material. Try again.") }
    }

    public func deliverSelection() {
        guard canDeliver, let target = selectedTarget, let onDeliver else { return }
        let batch = selection
        isDelivering = true
        error = nil
        onDeliver(batch, target) { [weak self] succeeded in
            guard let self else { return }
            self.isDelivering = false
            guard succeeded else {
                self.error = L10n.s("Handoff failed. Your selection is still here.")
                return
            }
            do {
                try self.store?.remove(ids: batch.map { $0.0.id })
                self.selectedIDs.subtract(batch.map { $0.0.id })
                self.reload()
            } catch {
                self.error = L10n.s("Handoff prepared, but these items could not be removed. Check the receiver before retrying.")
            }
        }
    }
}
