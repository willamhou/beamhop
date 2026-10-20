import Foundation

/// Session-level memory of the last delivery target the user actually succeeded with — the
/// panel pre-selects it next time (Week 3 wiring, spec §2.1 "记住上次选择").
/// 2026-10-19 (essay 02): also remembers the last NAMED destination (work) used, so the
/// panel re-binds to it and can surface an unconfirmed receiver change.
public struct TargetMemory {
    public private(set) var last: DeliveryTarget?
    public private(set) var lastWorkName: String?

    public init(default initial: DeliveryTarget? = .claudeCode) {
        last = initial
    }

    /// Only a SUCCESSFUL delivery updates memory; failures and "Inbox only" confirmations
    /// leave the previous choice intact.
    public mutating func markSucceeded(_ target: DeliveryTarget, workName: String? = nil) {
        last = target
        let name = workName?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastWorkName = name?.isEmpty == false ? name : nil
    }

    public mutating func reset() {
        last = nil
        lastWorkName = nil
    }
}
