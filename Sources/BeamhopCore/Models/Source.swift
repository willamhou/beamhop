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
}

/// Outcome of a delivery attempt (spec §8.1 deliveries.status).
public enum DeliveryStatus: String, Codable, Sendable {
    case success
    case failed
    case cancelled
}
