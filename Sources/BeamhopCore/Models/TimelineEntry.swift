import Foundation

/// One point on a Capture's detail-chain timeline (spec 2026-10-19-inbox-detail-chain §2.1):
/// what we sent out (`.delivery`) or what an agent gave back (`.result`). The merge/sort logic
/// lives here in Core — pure and testable (SelfTest + XCTest mirror); the Inbox UI only renders.
public enum TimelineEntry: Equatable, Sendable {
    case delivery(Delivery)
    case result(CaptureResult)

    /// unix ms — `delivered_at` for deliveries, `created_at` for results.
    public var timestamp: Int64 {
        switch self {
        case .delivery(let d): return d.deliveredAt
        case .result(let r): return r.createdAt
        }
    }

    /// Stable identity for SwiftUI rendering: result ids are ULIDs; deliveries fall back to
    /// their row id / timestamp (deliveries are Int64-rowid records, results are string-id).
    public var stableID: String {
        switch self {
        case .delivery(let d): return "dlv-\(d.id ?? d.deliveredAt)"
        case .result(let r): return r.id
        }
    }
}

public enum TimelineBuilder {
    /// Merge deliveries + results into one ascending timeline. Same-millisecond ties put the
    /// delivery first — the answer comes after the question.
    public static func entries(deliveries: [Delivery], results: [CaptureResult]) -> [TimelineEntry] {
        var all = deliveries.map(TimelineEntry.delivery) + results.map(TimelineEntry.result)
        all.sort { a, b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            switch (a, b) {
            case (.delivery, .result): return true
            case (.result, .delivery): return false
            default: return false
            }
        }
        return all
    }
}
