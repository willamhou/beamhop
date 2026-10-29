import Foundation
import Combine
import GRDB

/// Draft changes and individual handoff receipts commit atomically. History is stored
/// separately so typing never serializes or rewrites full-text handoff backups.
public final class HopLibrary: ObservableObject {
    public struct State: Codable, Equatable {
        public var active: HopDraft?
        public var pocket: [HopDraft] = []
        public var records: [HopRecord] = []
        public var routes: [HopRoute] = []
        public var projects: [String] = []
        public var lastRoute = HopRoute(target: .claudeCode)
        public var deletedDrafts: [HopDraft]?
        public var deletedDraftPositions: [String: Int]?
        public init() {}
    }
    @Published public private(set) var state: State
    public var onChange: (() -> Void)?
    public var onActivity: ((HopActivity) -> Void)?
    /// Retained local associations only; never guess a task for an old record.
    public var tasks: [HopTask] {
        let drafts = [state.active].compactMap { $0 } + state.pocket + state.records.reversed().map(\.draft)
        var seen = Set<String>()
        return drafts.compactMap(\.task).filter { seen.insert($0.id).inserted }
    }
    public func history(taskID: String) -> [HopRecord] {
        state.records.reversed().filter { $0.draft.task?.id == taskID }
    }
    public enum TaskError: LocalizedError {
        case unavailableSource, mixedTasks
        public var errorDescription: String? {
            switch self {
            case .unavailableSource: return L10n.s("The task or selected conclusion is no longer available.")
            case .mixedTasks: return L10n.s("Different tasks. Edit their task association or hand them off separately.")
            }
        }
    }
    /// Explicit continuation: select exactly one retained conclusion, never all history.
    public func continueTask(handoffID: String, resultID: String? = nil) throws {
        guard let record = state.records.first(where: { $0.id == handoffID }), record.draft.task != nil else {
            throw TaskError.unavailableSource
        }
        var draft = record.draft
        draft.id = UUID().uuidString
        draft.requestsResultReturn = false
        if let resultID {
            guard let result = try HandoffResultStore(database.queue).result(id: resultID), result.handoffID == handoffID else {
                throw TaskError.unavailableSource
            }
            let text = [draft.relay?.outgoingText ?? "", "Agent-reported conclusion (unverified):\n" + result.content]
                .filter { !$0.isEmpty }.joined(separator: "\n\n")
            draft.relay = HopRelayContext(text: text,
                                        sourceHandoffID: handoffID, sourceResultID: result.id)
        }
        try start(draft)
    }
    private let database: Database
    public init(_ database: Database) throws {
        self.database = database
        state = try database.queue.read { db in
            let json = try Data.fetchOne(db, sql: "SELECT payload FROM hop_state WHERE id = 1")
            var value = try json.map { try JSONDecoder().decode(State.self, from: $0) } ?? State()
            value.records = try Data.fetchAll(db, sql: "SELECT payload FROM hop_records ORDER BY position")
                .map { try JSONDecoder().decode(HopRecord.self, from: $0) }
            return value
        }
        // A process exit does not establish delivery failure; never retry automatically.
        let interrupted = state.records.filter { $0.status == .preparing }.map { record -> HopRecord in
            var updated = record
            updated.status = .failed
            updated.detail = L10n.s("Status unknown after restart. Check the receiving app before trying again.")
            return updated
        }
        if !interrupted.isEmpty {
            let updates = Dictionary(uniqueKeysWithValues: interrupted.map { ($0.id, $0) })
            try change(records: interrupted) { value in
                for index in value.records.indices where value.records[index].status == .preparing {
                    value.records[index] = updates[value.records[index].id]!
                }
            }
            for record in interrupted { recordActivity(HopActivity(.interrupted, id: record.id)) }
        }
    }
    private func recordActivity(_ activity: HopActivity) {
        EventStore(database).recordHop(activity)
        onActivity?(activity)
    }
    private func change(records: [HopRecord] = [], deletingRecords: Set<String> = [], _ edit: (inout State) -> Void) throws {
        var next = state; edit(&next)
        var drafts = next
        drafts.records = []
        let payload = try JSONEncoder().encode(drafts)
        let receipts = try records.map { ($0.id, try JSONEncoder().encode($0)) }
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO hop_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [payload])
            for (id, data) in receipts {
                try db.execute(sql: "INSERT INTO hop_records (id, payload) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
                               arguments: [id, data])
            }
            for id in deletingRecords { try db.execute(sql: "DELETE FROM hop_records WHERE id = ?", arguments: [id]) }
        }
        state = next; onChange?()
    }
    public func saveActive(_ draft: HopDraft) throws {
        guard state.active != draft else { return }
        try change { $0.active = draft }
    }
    private static func park(_ draft: HopDraft?, in value: inout State) {
        guard let draft, draft.hasContent else { return }
        if let index = value.pocket.firstIndex(where: { $0.id == draft.id }) { value.pocket[index] = draft }
        else { value.pocket.append(draft) }
    }
    public func start(_ draft: HopDraft) throws {
        try change { value in
            if value.active?.id != draft.id { Self.park(value.active, in: &value) }
            value.active = draft
        }
    }
    public func hold(_ draft: HopDraft) throws {
        try hold(draft, trackUsage: true)
    }
    /// Legacy restoration is not a new user's Pocket save action.
    public func importLegacyDraft(_ draft: HopDraft) throws {
        try hold(draft, trackUsage: false)
    }
    private func hold(_ draft: HopDraft, trackUsage: Bool) throws {
        try change { value in
            Self.park(draft, in: &value)
            if value.active?.id == draft.id { value.active = nil }
        }
        if trackUsage { recordActivity(HopActivity(.saved, id: draft.id)) }
    }
    public func restore(_ id: String) throws {
        guard let draft = state.pocket.first(where: { $0.id == id }) else { return }
        try change { value in
            value.pocket.removeAll { $0.id == id }
            Self.park(value.active, in: &value)
            value.active = draft
        }
        recordActivity(HopActivity(.restored, id: id))
    }
    public func addMaterials(from draft: HopDraft) throws {
        try change { value in
            var active = value.active ?? HopDraft(materials: [], route: value.lastRoute)
            active.materials += draft.materials.map { var copy = $0; copy.id = UUID().uuidString; return copy }
            value.active = active
        }
        recordActivity(HopActivity(.reused, id: draft.id))
    }
    public func recover(_ record: HopRecord) throws {
        var draft = record.draft; draft.id = UUID().uuidString
        try start(draft)
        recordActivity(HopActivity(.recovered, id: record.id))
    }
    public func remember(_ route: HopRoute) throws {
        try change { value in
            value.lastRoute = route
            if !value.routes.contains(route) { value.routes.append(route) }
            if !route.project.isEmpty && !value.projects.contains(route.project) { value.projects.append(route.project) }
        }
    }
    public func begin(_ draft: HopDraft) throws -> HopRecord {
        let record = HopRecord(draft: draft)
        try change(records: [record]) { $0.records.append(record) }
        recordActivity(HopActivity(.started, id: record.id))
        return record
    }
    public func beginBatch(_ drafts: [HopDraft], route: HopRoute, requestsResultReturn: Bool? = nil) throws -> HopRecord {
        guard route.target != nil, !drafts.isEmpty, drafts.allSatisfy({ state.pocket.contains($0) && !inFlightIDs.contains($0.id) }) else {
            throw PocketError.changed
        }
        guard drafts.allSatisfy({ $0.task?.id == drafts.first?.task?.id }) else { throw TaskError.mixedTasks }
        var combined: HopDraft
        if drafts.count == 1 { combined = drafts[0]; combined.route = route }
        else {
            // Preserve each instruction next to its own material, in shelf order.
            let materials = drafts.flatMap { draft -> [HopMaterial] in
                let context = [draft.route.project, draft.instruction, draft.relay?.outgoingText ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
                let copied = draft.materials.map { material -> HopMaterial in
                    var copy = material; copy.id = UUID().uuidString; return copy
                }
                return (context.isEmpty ? [] : [HopMaterial(text: context)]) + copied
            }
            combined = HopDraft(materials: materials, route: route)
            combined.task = drafts.first?.task
        }
        combined.requestsResultReturn = requestsResultReturn ?? drafts.allSatisfy(\.requestsResultReturn)
        var record = HopRecord(draft: combined)
        record.pocketSources = drafts
        try change(records: [record]) { $0.records.append(record) }
        recordActivity(HopActivity(.started, id: record.id, sourceDraftIDs: drafts.map(\.id)))
        return record
    }
    public enum PocketError: LocalizedError {
        case changed
        public var errorDescription: String? { L10n.s("These drafts changed or are being handed off. Select them again.") }
    }
    public var inFlightIDs: Set<String> {
        Set(state.records.filter { $0.status == .preparing }.flatMap { ($0.pocketSources ?? [$0.draft]).map(\.id) })
    }
    public func deleteDrafts(_ ids: Set<String>) throws {
        guard ids.isDisjoint(with: inFlightIDs) else { throw PocketError.changed }
        let removed = state.pocket.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        try change { value in
            value.deletedDrafts = removed
            value.deletedDraftPositions = Dictionary(uniqueKeysWithValues: value.pocket.enumerated()
                .filter { ids.contains($0.element.id) }.map { ($0.element.id, $0.offset) })
            value.pocket.removeAll { ids.contains($0.id) }
        }
    }
    public func undoDeleteDrafts() throws {
        try change { value in
            for draft in value.deletedDrafts ?? [] where value.active?.id != draft.id && !value.pocket.contains(where: { $0.id == draft.id }) {
                value.pocket.insert(draft, at: min(value.deletedDraftPositions?[draft.id] ?? value.pocket.count, value.pocket.count))
            }
            value.deletedDrafts = nil
            value.deletedDraftPositions = nil
        }
    }
    public func duplicate(_ draft: HopDraft) throws {
        var copy = draft; copy.id = UUID().uuidString
        copy.materials = copy.materials.map { var material = $0; material.id = UUID().uuidString; return material }
        try hold(copy)
    }
    public func deleteRecords(_ ids: Set<String>) throws {
        let removable = Set(state.records.filter { ids.contains($0.id) && $0.status != .preparing }.map(\.id))
        try change(deletingRecords: removable) { $0.records.removeAll { removable.contains($0.id) } }
    }
    public func finish(_ id: String, status: HopRecord.Status, detail: String? = nil) throws {
        guard let index = state.records.firstIndex(where: { $0.id == id }) else { return }
        let previous = state.records[index]
        var record = state.records[index]
        record.status = status; record.detail = detail
        try change(records: [record]) { value in
            value.records[index] = record
            // Failure retains input. A successful late completion consumes only its exact
            // snapshot, even if a new capture parked it while delivery was in flight.
            if status == .prepared || status == .copied {
                if value.active == record.draft { value.active = nil }
                let sources = record.pocketSources ?? [record.draft]
                value.pocket.removeAll { sources.contains($0) }
            }
        }
        if previous.status != status || previous.detail != detail {
            let kind: HopActivity.Kind
            switch status {
            case .preparing: return
            case .copied: kind = .copied
            case .prepared: kind = .prepared
            case .failed: kind = .failed
            }
            recordActivity(HopActivity(kind, id: id, readableFailure: detail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false))
        }
    }
}
