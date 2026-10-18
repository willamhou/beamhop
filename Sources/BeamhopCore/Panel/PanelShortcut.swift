import Foundation

/// Week 3 capture-panel keyboard shortcuts (spec §2.1): ⌘1/2/3/4 pick a delivery target,
/// ⌘0 is the explicit "Inbox only" no-delivery choice (distinct from Esc-cancel).
/// Single source of truth so the SwiftUI buttons and any key routing can't drift apart.
public enum PanelShortcut: String, CaseIterable, Sendable {
    case claudeCode = "1"
    case chatgptDesktop = "2"
    case cowork = "3"
    case kimiWork = "4"
    case inboxOnly = "0"

    /// nil = "仅入 Inbox" — an explicit no-delivery choice, NOT a cancel.
    public var target: DeliveryTarget? {
        switch self {
        case .claudeCode: return .claudeCode
        case .chatgptDesktop: return .chatgptDesktop
        case .cowork: return .cowork
        case .kimiWork: return .kimiWork
        case .inboxOnly: return nil
        }
    }

    public var badge: String { "⌘\(rawValue)" }
}
