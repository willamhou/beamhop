import Foundation

public enum DiagnosticCheckID: String, Codable, CaseIterable, Sendable {
    case accessibility, screenRecording = "screen_recording", chromeHost = "chrome_host"
    case claudeMCP = "claude_mcp", cowork, chatGPT = "chatgpt", hotkeys
}
public enum DiagnosticStatus: String, Codable, Sendable { case ok, fail, warn, todo }
public struct DiagnosticCheck: Codable, Equatable, Sendable {
    public let id: DiagnosticCheckID
    public let status: DiagnosticStatus
    public init(id: DiagnosticCheckID, status: DiagnosticStatus) { self.id = id; self.status = status }
}

/// Privacy by construction: no free-form details/logs/config, capture or database input exists.
public struct DiagnosticReport: Encodable, Sendable {
    public let schemaVersion = 1
    public let build: BuildInfo
    public let macOSVersion: String
    public let runtimeArchitecture: String
    public let checks: [DiagnosticCheck]
    public let privacy = "Allowlisted local report; no logs, paths, URLs, capture content, notes, sessions, configuration, credentials or device identifiers."

    public init(build: BuildInfo, macOSVersion: String, runtimeArchitecture: String, checks: [DiagnosticCheck]) {
        self.build = build
        self.macOSVersion = BuildInfo.numericVersion(macOSVersion)
        self.runtimeArchitecture = ["arm64", "x86_64"].contains(runtimeArchitecture) ? runtimeArchitecture : "unknown"
        // Stable order, unique known IDs. No caller-provided labels or details reach the report.
        self.checks = DiagnosticCheckID.allCases.compactMap { id in checks.first { $0.id == id } }
    }
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", build, macOSVersion = "macos_version"
        case runtimeArchitecture = "runtime_architecture", checks, privacy
    }
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
