import Foundation

/// Total wall-clock budget for one AX read pass (PROGRESS §7.D: "AX 整体 800ms deadline").
///
/// Individual AX calls each set a 0.8s messaging timeout, but a slow target app could still
/// stack several of them into a multi-second capture. `AXDeadline` bounds the WHOLE
/// `AXHelper.read` sequence: helpers check `expired` between steps and shrink per-call
/// timeouts to `min(default, remaining)` so no single call can outlive the budget by much.
public struct AXDeadline {
    private let start: Date
    public let budget: TimeInterval

    public init(budget: TimeInterval = 0.8) {
        self.start = Date()
        self.budget = max(0, budget)
    }

    public var elapsed: TimeInterval { Date().timeIntervalSince(start) }

    /// True once the budget is exhausted — callers should stop and return partials.
    public var expired: Bool { elapsed >= budget }

    /// Budget still available, clamped at zero.
    public var remaining: TimeInterval { max(0, budget - elapsed) }

    /// Per-call AX messaging timeout that cannot exceed the remaining budget.
    public func callTimeout(default def: Double) -> Double {
        max(0.05, min(def, remaining))
    }
}
