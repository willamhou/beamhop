import Foundation
import Combine
import GRDB

/// One transactional state document keeps restoration and current-input preservation atomic.
public final class HopLibrary: ObservableObject {
    public struct State: Codable, Equatable {
        public var active: HopDraft?
        public var pocket: [HopDraft] = []
        public var records: [HopRecord] = []
        public var routes: [HopRoute] = []
        public var projects: [String] = []
        public var lastRoute = HopRoute(target: .claudeCode)
        public init() {}
    }
    @Published public private(set) var state: State
    public var onChange: (() -> Void)?
    private let database: Database
    public init(_ database: Database) throws {
        self.database = database
        state = try database.queue.read { db in
            guard let json = try Data.fetchOne(db, sql: "SELECT payload FROM hop_state WHERE id = 1") else { return State() }
            return try JSONDecoder().decode(State.self, from: json)
        }
        // A process exit does not establish delivery failure; never retry automatically.
        if state.records.contains(where: { $0.status == .preparing }) {
            try change { value in
                for index in value.records.indices where value.records[index].status == .preparing {
                    value.records[index].status = .failed
                    value.records[index].detail = L10n.s("Status unknown after restart. Check the receiving app before trying again.")
                }
            }
        }
    }
    private func change(_ edit: (inout State) -> Void) throws {
        var next = state; edit(&next)
        let payload = try JSONEncoder().encode(next)
        try database.queue.write { db in
            try db.execute(sql: "INSERT INTO hop_state (id, payload) VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload", arguments: [payload])
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
        try change { value in
            Self.park(draft, in: &value)
            if value.active?.id == draft.id { value.active = nil }
        }
    }
    public func restore(_ id: String) throws {
        guard let draft = state.pocket.first(where: { $0.id == id }) else { return }
        try change { value in
            value.pocket.removeAll { $0.id == id }
            Self.park(value.active, in: &value)
            value.active = draft
        }
    }
    public func addMaterials(from draft: HopDraft) throws {
        try change { value in
            var active = value.active ?? HopDraft(materials: [], route: value.lastRoute)
            active.materials += draft.materials.map { var copy = $0; copy.id = UUID().uuidString; return copy }
            value.active = active
        }
    }
    public func recover(_ record: HopRecord) throws {
        var draft = record.draft; draft.id = UUID().uuidString
        try start(draft)
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
        try change { $0.records.append(record) }
        return record
    }
    public func finish(_ id: String, status: HopRecord.Status, detail: String? = nil) throws {
        try change { value in
            guard let index = value.records.firstIndex(where: { $0.id == id }) else { return }
            value.records[index].status = status; value.records[index].detail = detail
            // A late completion cannot consume a newer edit or a newly captured batch.
            if value.active == value.records[index].draft { value.active = nil }
        }
    }
}
