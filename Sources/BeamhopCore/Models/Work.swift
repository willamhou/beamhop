import Foundation
import GRDB

/// A named destination — the two-layer routing idea from product essay 02 (2026-10-19):
/// the TOP layer is the work the human recognizes ("让发送不打断阅读"); the BOTTOM layer is
/// the receiving app it is currently bound to (`.claudeCode` etc.).
///
/// This is a human label for an app destination, not a verified conversation address.
/// A work may outlive any single session. When the binding is REBOUND to a different
/// receiver, `needsConfirmation` becomes true and stays true until the user explicitly
/// confirms the new receiver at delivery time — a similar name must never silently
/// redirect material (essay 02: "更新接收会话时，必须核对新的地址").
public struct Work: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "works"

    public var id: String                 // "wrk_<ulid>"
    public var name: String               // 人认得的工作名, unique (case-insensitive in store layer)
    public var boundTarget: DeliveryTarget   // app binding only; no conversation identity
    /// The receiver the user last EXPLICITLY confirmed. nil = never confirmed under this name
    /// (e.g. restored/default); confirm at next delivery.
    public var confirmedTarget: DeliveryTarget?
    public var createdAt: Int64
    public var updatedAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case boundTarget = "bound_target"
        case confirmedTarget = "confirmed_target"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Rebind changed the receiver and the user has not confirmed the new address yet.
    public var needsConfirmation: Bool { confirmedTarget != boundTarget }

    public init(id: String = ULID.workID(),
                name: String,
                boundTarget: DeliveryTarget,
                confirmedTarget: DeliveryTarget? = nil,
                createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.name = name
        self.boundTarget = boundTarget
        self.confirmedTarget = confirmedTarget
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {}
}
