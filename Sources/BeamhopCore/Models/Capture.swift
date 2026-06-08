import Foundation
import GRDB

/// A captured piece of context + full provenance (spec §6.5 + §12.1).
/// Maps to the `captures` table. Column names are spelled out via CodingKeys to avoid
/// camelCase→snake_case acronym ambiguity (appBundleID, pid, captureDurationMs, …).
public struct Capture: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "captures"

    // Core (spec §6.5)
    public var id: String                 // "cap_<ulid>"
    public var createdAt: Int64           // unix ms
    public var source: Source
    public var appBundleID: String
    public var appName: String
    public var windowTitle: String?
    public var url: String?
    public var selectedText: String?
    public var extractedBody: String?
    public var domainHint: DomainHint?
    public var userNote: String?
    public var screenshotPath: String?
    public var deletedAt: Int64?          // soft delete (unix ms); physically purged after 30d

    // Provenance (spec §12.1)
    public var pid: Int
    public var appVersion: String?
    public var osVersion: String
    public var beamhopVersion: String
    public var axTreeSnapshot: String?    // JSON
    public var captureMethod: String      // the channel that actually produced this
    public var extensionVersion: String?
    public var isPrivate: Bool
    public var truncated: Bool
    public var captureDurationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case source
        case appBundleID = "app_bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case url
        case selectedText = "selected_text"
        case extractedBody = "extracted_body"
        case domainHint = "domain_hint"
        case userNote = "user_note"
        case screenshotPath = "screenshot_path"
        case deletedAt = "deleted_at"
        case pid
        case appVersion = "app_version"
        case osVersion = "os_version"
        case beamhopVersion = "beamhop_version"
        case axTreeSnapshot = "ax_tree_snapshot"
        case captureMethod = "capture_method"
        case extensionVersion = "extension_version"
        case isPrivate = "is_private"
        case truncated
        case captureDurationMs = "capture_duration_ms"
    }

    public init(
        id: String = ULID.captureID(),
        createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        source: Source,
        appBundleID: String,
        appName: String,
        windowTitle: String? = nil,
        url: String? = nil,
        selectedText: String? = nil,
        extractedBody: String? = nil,
        domainHint: DomainHint? = nil,
        userNote: String? = nil,
        screenshotPath: String? = nil,
        deletedAt: Int64? = nil,
        pid: Int,
        appVersion: String? = nil,
        osVersion: String = Version.os,
        beamhopVersion: String = Version.beamhop,
        axTreeSnapshot: String? = nil,
        captureMethod: String,
        extensionVersion: String? = nil,
        isPrivate: Bool = false,
        truncated: Bool = false,
        captureDurationMs: Int? = nil
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
        self.domainHint = domainHint
        self.userNote = userNote
        self.screenshotPath = screenshotPath
        self.deletedAt = deletedAt
        self.pid = pid
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.beamhopVersion = beamhopVersion
        self.axTreeSnapshot = axTreeSnapshot
        self.captureMethod = captureMethod
        self.extensionVersion = extensionVersion
        self.isPrivate = isPrivate
        self.truncated = truncated
        self.captureDurationMs = captureDurationMs
    }
}
