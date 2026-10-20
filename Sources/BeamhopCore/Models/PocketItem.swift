import Foundation
import GRDB

/// One held ("先留着") piece of material (product essay 01/02, 2026-10-19): the user chose
/// NOT to deliver yet — the pocket keeps the capture, the note (交代), the intended target,
/// and the ORDER items were held in, so an interrupted stack comes back exactly as left.
/// Maps to `pocket_items`; FK cascade like deliveries (v2 pattern) — purging a capture
/// never orphans pocket rows.
public struct PocketItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "pocket_items"

    public var id: String                 // "pok_<ulid>"
    public var captureID: String
    public var note: String?              // 交代, verbatim
    public var workName: String?          // intent snapshot; never resolves a new receiver silently
    public var intendedTarget: DeliveryTarget?   // nil = 还没想好给谁
    public var position: Int              // ascending hold order; the stack is ordered
    public var createdAt: Int64           // unix ms

    enum CodingKeys: String, CodingKey {
        case id
        case captureID = "capture_id"
        case note
        case workName = "work_name"
        case intendedTarget = "intended_target"
        case position
        case createdAt = "created_at"
    }

    public init(id: String = ULID.pocketID(),
                captureID: String,
                note: String? = nil,
                workName: String? = nil,
                intendedTarget: DeliveryTarget? = nil,
                position: Int,
                createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.id = id
        self.captureID = captureID
        self.note = note
        self.workName = workName
        self.intendedTarget = intendedTarget
        self.position = position
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {}
}
