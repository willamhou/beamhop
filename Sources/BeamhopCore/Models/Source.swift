import Foundation

/// How a Capture's content was obtained (spec §6.5).
public enum Source: String, Codable, CaseIterable, Sendable {
    case browser
    case ax
    case screenshot
}

/// Structured hint about the source domain (spec §6.5). Raw values match the spec's dotted form.
public enum DomainHint: String, Codable, CaseIterable, Sendable {
    case githubPR = "github.pr"
    case githubIssue = "github.issue"
    case githubRepo = "github.repo"
    case githubCode = "github.code"
    case stackoverflow = "stackoverflow"
    case generic = "generic"
}

/// Delivery target for a Capture (spec §8.1 deliveries.target).
public enum DeliveryTarget: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude_code"
    case cowork = "cowork"
    case chatgptDesktop = "chatgpt_desktop"
    case clipboard = "clipboard"
    case kimiWork = "kimi_work"      // Week 3+: AX-locate + clipboard-paste into Kimi desktop
}

/// Outcome of a delivery attempt (spec §8.1 deliveries.status).
public enum DeliveryStatus: String, Codable, Sendable {
    /// Legacy records do not identify how far the old transport got.
    case success
    case copied
    case prepared
    case failed
    case cancelled

    public var isSuccessful: Bool { self == .success || self == .copied || self == .prepared }

    public var displayName: String {
        switch self {
        case .success: return L10n.s("Handoff recorded")
        case .copied: return L10n.s("Copied")
        case .prepared: return L10n.s("Prepared · awaiting your send")
        case .failed: return L10n.s("Handoff failed")
        case .cancelled: return L10n.s("Cancelled")
        }
    }
}
