import Foundation

/// Session-level memory of the last delivery target the user actually succeeded with — the
/// panel pre-selects it next time (Week 3 wiring, spec §2.1 "记住上次选择").
public struct TargetMemory {
    public private(set) var last: DeliveryTarget?

    public init(default initial: DeliveryTarget? = .claudeCode) {
        last = initial
    }

    /// Only a SUCCESSFUL delivery updates memory; failures and "Inbox only" confirmations
    /// leave the previous choice intact.
    public mutating func markSucceeded(_ target: DeliveryTarget) {
        last = target
    }

    public mutating func reset() {
        last = nil
    }
}
