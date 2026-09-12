@preconcurrency import Foundation

public enum CaptureSource: String, Codable, CaseIterable, Sendable {
    case browser
    case ax
    case screenshot
}

/// How the final payload was obtained. `source` describes its semantic source;
/// `captureMethod` records the channel that actually succeeded.
public enum CaptureMethod: String, Codable, CaseIterable, Sendable {
    case accessibility = "ax"
    case browserExtension = "browser_extension"
    case screenshot
    case merged
    case manual
}

public struct CaptureProvenance: Codable, Equatable, Sendable {
    public var processID: Int
    public var appVersion: String?
    public var operatingSystemVersion: String
    public var beamhopVersion: String
    public var accessibilityTreeSnapshot: String?
    public var captureMethod: CaptureMethod
    public var extensionVersion: String?
    public var isPrivate: Bool
    public var isTruncated: Bool
    public var captureDurationMilliseconds: Int?

    public init(
        processID: Int,
        appVersion: String? = nil,
        operatingSystemVersion: String,
        beamhopVersion: String,
        accessibilityTreeSnapshot: String? = nil,
        captureMethod: CaptureMethod,
        extensionVersion: String? = nil,
        isPrivate: Bool = false,
        isTruncated: Bool = false,
        captureDurationMilliseconds: Int? = nil
    ) {
        self.processID = processID
        self.appVersion = appVersion
        self.operatingSystemVersion = operatingSystemVersion
        self.beamhopVersion = beamhopVersion
        self.accessibilityTreeSnapshot = accessibilityTreeSnapshot
        self.captureMethod = captureMethod
        self.extensionVersion = extensionVersion
        self.isPrivate = isPrivate
        self.isTruncated = isTruncated
        self.captureDurationMilliseconds = captureDurationMilliseconds
    }
}

public struct Capture: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var createdAt: Date
    public var source: CaptureSource
    public var appBundleID: String
    public var appName: String
    public var windowTitle: String?
    public var url: URL?
    public var selectedText: String?
    public var extractedBody: String?
    public var screenshotPath: String?
    public var userNote: String?
    /// Stable dotted value such as `github.pr`, `stackoverflow`, or `generic`.
    public var domainHint: String?
    public var provenance: CaptureProvenance
    public var deletedAt: Date?

    public init(
        id: String = CaptureID.generate(),
        createdAt: Date = Date(),
        source: CaptureSource,
        appBundleID: String,
        appName: String,
        windowTitle: String? = nil,
        url: URL? = nil,
        selectedText: String? = nil,
        extractedBody: String? = nil,
        screenshotPath: String? = nil,
        userNote: String? = nil,
        domainHint: String? = nil,
        provenance: CaptureProvenance,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.source = source
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.selectedText = selectedText
        self.extractedBody = extractedBody
        self.screenshotPath = screenshotPath
        self.userNote = userNote
        self.domainHint = domainHint
        self.provenance = provenance
        self.deletedAt = deletedAt
    }
}

public enum CaptureID {
    /// A compact, filesystem-safe identifier. The timestamp prefix preserves
    /// creation order and 64 bits of UUID entropy make collisions negligible.
    public static func generate(at date: Date = Date()) -> String {
        let milliseconds = UInt64(max(0, date.timeIntervalSince1970 * 1_000))
        let time = String(milliseconds, radix: 36)
        let entropy = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            .prefix(16).lowercased()
        return "cap_\(time)\(entropy)"
    }
}

public enum DeliveryTarget: String, Codable, CaseIterable, Sendable {
    case claudeCode = "claude_code"
    case claudeCowork = "cowork"
    case chatGPTDesktop = "chatgpt_desktop"
    case clipboard
}

public enum DeliveryStatus: String, Codable, CaseIterable, Sendable {
    case success
    case failed
    case cancelled
}

public struct Delivery: Codable, Identifiable, Equatable, Sendable {
    public var id: Int64?
    public var captureID: String
    public var target: DeliveryTarget
    public var deliveredAt: Date
    public var status: DeliveryStatus
    public var errorMessage: String?

    public init(
        id: Int64? = nil,
        captureID: String,
        target: DeliveryTarget,
        deliveredAt: Date = Date(),
        status: DeliveryStatus,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.captureID = captureID
        self.target = target
        self.deliveredAt = deliveredAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct CaptureSearchResult: Equatable, Sendable {
    public let capture: Capture
    /// Lower is better. It combines FTS5 BM25 with a small age penalty.
    public let score: Double

    public init(capture: Capture, score: Double) {
        self.capture = capture
        self.score = score
    }
}
