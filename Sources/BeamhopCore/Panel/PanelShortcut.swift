import Foundation

/// Week 3 capture-panel keyboard shortcuts (spec §2.1): ⌘1/2/3/4 pick a delivery target,
/// ⌘0 is the explicit "Inbox only" no-delivery choice (distinct from Esc-cancel), ⌘5 (2026-10-19,
/// product essay 01) is 「先留着」— park the capture in the hold stack instead of delivering.
/// Single source of truth so the SwiftUI buttons and any key routing can't drift apart.
public enum PanelShortcut: String, CaseIterable, Sendable {
    case claudeCode = "1"
    case chatgptDesktop = "2"
    case cowork = "3"
    case kimiWork = "4"
    case inboxOnly = "0"
    case hold = "5"

    /// nil = "仅入 Inbox" — an explicit no-delivery choice, NOT a cancel. Also nil for
    /// `.hold` (it parks rather than delivers); use `isHold` to disambiguate.
    public var target: DeliveryTarget? {
        switch self {
        case .claudeCode: return .claudeCode
        case .chatgptDesktop: return .chatgptDesktop
        case .cowork: return .cowork
        case .kimiWork: return .kimiWork
        case .inboxOnly, .hold: return nil
        }
    }

    /// 「先留着」: hold (essay 01) — nil target like inboxOnly, but a distinct action.
    public var isHold: Bool { self == .hold }

    public var badge: String { "⌘\(rawValue)" }
}
