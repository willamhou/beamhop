import Foundation
import GRDB

/// A delivery attempt of a Capture to a target (spec §8.1 deliveries).
public struct Delivery: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "deliveries"

    public var id: Int64?
    public var captureID: String
    public var target: DeliveryTarget
    public var deliveredAt: Int64        // unix ms
    public var status: DeliveryStatus
    public var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case captureID = "capture_id"
        case target
        case deliveredAt = "delivered_at"
        case status
        case errorMessage = "error_message"
    }

    public init(
        id: Int64? = nil,
        captureID: String,
        target: DeliveryTarget,
        deliveredAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        status: DeliveryStatus,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.captureID = captureID
        self.target = target
        self.deliveredAt = deliveredAt
        self.status = status
        self.errorMessage = errorMessage
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
