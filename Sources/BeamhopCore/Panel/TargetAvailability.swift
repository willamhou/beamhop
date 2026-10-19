import Foundation

/// Which delivery targets are REAL on this machine (2026-10-19 UI pass: the panel should
/// only offer destinations that actually exist — offering "ChatGPT" to someone without the
/// app, or "Cowork" whose integration is still S2-pending, is a fake choice).
/// Pure decision function: the Beamhop app layer probes the machine (NSWorkspace /
/// FileManager, see TargetDetector) and feeds the booleans in; Core stays testable.
public enum TargetAvailability {
    /// Ordered like the panel rows: app targets first, clipboard always last-resort-visible.
    /// `.cowork` never appears — no integration exists yet; clipboard covers its honest form.
    public static func resolve(hasClaudeCLI: Bool,
                               hasChatGPTApp: Bool,
                               hasKimiApp: Bool) -> [DeliveryTarget] {
        var result: [DeliveryTarget] = []
        if hasClaudeCLI { result.append(.claudeCode) }
        if hasChatGPTApp { result.append(.chatgptDesktop) }
        if hasKimiApp { result.append(.kimiWork) }
        result.append(.clipboard)   // always available, honest fallback
        return result
    }

    /// Keep the remembered/initial target only if it's still deliverable here;
    /// otherwise fall back to the first available target (or nil = Inbox when empty).
    public static func usable(_ target: DeliveryTarget?, among available: [DeliveryTarget]) -> DeliveryTarget? {
        guard let target else { return nil }
        return available.contains(target) ? target : (available.first ?? nil)
    }
}
