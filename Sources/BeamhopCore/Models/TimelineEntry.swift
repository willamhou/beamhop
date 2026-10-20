import Foundation

/// The transport attempt and the agent's answer remain distinct, linked to the same capture.
public enum TimelineEntry: Equatable, Sendable {
    case delivery(Delivery)
    case result(CaptureResult)

    public var timestamp: Int64 {
        switch self {
        case .delivery(let delivery): return delivery.deliveredAt
        case .result(let result): return result.createdAt
        }
    }

    public var stableID: String {
        switch self {
        case .delivery(let delivery): return "dlv-\(delivery.id ?? delivery.deliveredAt)"
        case .result(let result): return result.id
        }
    }
}

public enum TimelineBuilder {
    /// Chronological order; transport precedes a conclusion at the same millisecond.
    public static func entries(deliveries: [Delivery], results: [CaptureResult]) -> [TimelineEntry] {
        (deliveries.map(TimelineEntry.delivery) + results.map(TimelineEntry.result)).sorted { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            switch (a, b) {
            case (.delivery, .result): return true
            case (.result, .delivery): return false
            default: return a.stableID < b.stableID
            }
        }
    }
}
