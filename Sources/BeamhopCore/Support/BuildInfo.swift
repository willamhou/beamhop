import Foundation

/// Allowlisted provenance. Never includes a checkout path, branch name, user or environment.
public struct BuildInfo: Codable, Equatable, Sendable {
    public enum Signing: String, Codable, Sendable { case adhoc, identity, unknown }
    public let schemaVersion: Int
    public let appVersion: String
    public let buildNumber: String
    public let buildID: String
    public let commit: String
    public let sourceDirty: Bool?
    public let sourceFingerprint: String
    public let builtAtUTC: String
    public let configuration: String
    public let architecture: String
    public let swiftVersion: String
    public let signing: Signing

    public init(appVersion: String = "unknown", buildNumber: String = "unknown",
                buildID: String = "unknown", commit: String = "unknown", sourceDirty: Bool? = nil,
                sourceFingerprint: String = "unknown", builtAtUTC: String = "unknown",
                configuration: String = "unknown", architecture: String = "unknown",
                swiftVersion: String = "unknown", signing: Signing = .unknown) {
        self.schemaVersion = 1
        self.appVersion = Self.numericVersion(appVersion)
        self.buildNumber = Self.allow(buildNumber, #"[0-9]{1,20}"#)
        self.buildID = UUID(uuidString: buildID)?.uuidString.lowercased() ?? "unknown"
        self.commit = Self.allow(commit.lowercased(), #"(?:[0-9a-f]{40}|[0-9a-f]{64})"#)
        self.sourceDirty = sourceDirty
        self.sourceFingerprint = Self.allow(sourceFingerprint.lowercased(), #"[0-9a-f]{64}"#)
        self.builtAtUTC = Self.allow(builtAtUTC, #"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"#)
        self.configuration = ["debug", "release"].contains(configuration) ? configuration : "unknown"
        self.architecture = ["arm64", "x86_64", "universal"].contains(architecture) ? architecture : "unknown"
        self.swiftVersion = Self.numericVersion(swiftVersion)
        self.signing = signing
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", appVersion = "app_version", buildNumber = "build_number"
        case buildID = "build_id", commit, sourceDirty = "source_dirty", sourceFingerprint = "source_fingerprint"
        case builtAtUTC = "built_at_utc", configuration, architecture, swiftVersion = "swift_version", signing
    }

    /// Decode through the same filters; even a tampered/foreign manifest cannot export arbitrary strings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: c, debugDescription: "Unsupported build schema")
        }
        self.init(appVersion: try c.decode(String.self, forKey: .appVersion),
                  buildNumber: try c.decode(String.self, forKey: .buildNumber),
                  buildID: try c.decode(String.self, forKey: .buildID),
                  commit: try c.decode(String.self, forKey: .commit),
                  sourceDirty: try c.decodeIfPresent(Bool.self, forKey: .sourceDirty),
                  sourceFingerprint: try c.decode(String.self, forKey: .sourceFingerprint),
                  builtAtUTC: try c.decode(String.self, forKey: .builtAtUTC),
                  configuration: try c.decode(String.self, forKey: .configuration),
                  architecture: try c.decode(String.self, forKey: .architecture),
                  swiftVersion: try c.decode(String.self, forKey: .swiftVersion),
                  signing: try c.decode(Signing.self, forKey: .signing))
    }

    public static func load(bundle: Bundle = .main) -> BuildInfo {
        if let url = bundle.url(forResource: "build-info", withExtension: "json"),
           let data = try? Data(contentsOf: url), data.count <= 32_768,
           let info = try? JSONDecoder().decode(BuildInfo.self, from: data) { return info }
        // SwiftPM and older packages must never invent a commit or claim a clean source tree.
        return BuildInfo(appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                         buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
    }

    public var shortCommit: String { commit == "unknown" ? "unknown" : String(commit.prefix(7)) }
    public var sourceLabel: String {
        switch sourceDirty {
        case true: return L10n.s("Local changes")
        case false: return L10n.s("Clean build inputs")
        case nil: return L10n.s("Source state unavailable")
        }
    }
    public var summary: String { "\(appVersion) (\(buildNumber)) · \(shortCommit) · \(sourceLabel)" }
    public static func numericVersion(_ value: String) -> String { allow(value, #"[0-9]{1,6}(?:\.[0-9]{1,6}){0,3}"#) }
    private static func allow(_ value: String, _ pattern: String) -> String {
        guard value.count <= 128, value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil else { return "unknown" }
        return value
    }
}
