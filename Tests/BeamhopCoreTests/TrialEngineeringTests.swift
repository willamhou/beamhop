import Foundation
import XCTest
@testable import BeamhopCore

final class TrialEngineeringTests: XCTestCase {
    func testBuildInfoFiltersUntrustedManifestAndUnknownKeys() throws {
        let source = """
        {"schema_version":1,"app_version":"0.1.0","build_number":"1",
        "build_id":"/Users/private/token","commit":"secret@example.com","source_dirty":true,
        "source_fingerprint":"https://private.invalid","built_at_utc":"private note",
        "configuration":"/Users/private","architecture":"device-serial","swift_version":"secret",
        "signing":"adhoc","notes":"TOP_SECRET","environment":{"token":"TOKEN_SECRET"}}
        """
        let info = try JSONDecoder().decode(BuildInfo.self, from: Data(source.utf8))
        XCTAssertEqual(info.commit, "unknown")
        XCTAssertEqual(info.buildID, "unknown")
        XCTAssertEqual(info.sourceFingerprint, "unknown")
        XCTAssertEqual(info.architecture, "unknown")
        XCTAssertEqual(info.sourceDirty, true)
        let report = DiagnosticReport(build: info, macOSVersion: "26.0.1", runtimeArchitecture: "arm64",
                                      checks: [.init(id: .accessibility, status: .warn)])
        let json = String(decoding: try report.jsonData(), as: UTF8.self)
        for value in ["/Users/private", "secret@example", "private.invalid", "private note", "device-serial", "TOP_SECRET", "TOKEN_SECRET"] {
            XCTAssertFalse(json.contains(value), value)
        }
    }

    func testProvenanceRoundTripsAndShortCommitIsHonest() throws {
        let info = BuildInfo(appVersion: "0.1.0", buildNumber: "7",
                             buildID: "f0ab1c2d-1234-4321-abcd-123456789abc",
                             commit: String(repeating: "a", count: 40), sourceDirty: false,
                             sourceFingerprint: String(repeating: "b", count: 64),
                             builtAtUTC: "2026-10-21T01:02:03Z", configuration: "release",
                             architecture: "arm64", swiftVersion: "6.4.0", signing: .adhoc)
        XCTAssertEqual(try JSONDecoder().decode(BuildInfo.self, from: JSONEncoder().encode(info)), info)
        XCTAssertEqual(info.shortCommit, "aaaaaaa")
        XCTAssertTrue(info.summary.contains("0.1.0 (7)"))
        XCTAssertNil(BuildInfo().sourceDirty)
        XCTAssertEqual(BuildInfo().shortCommit, "unknown")
        XCTAssertEqual(BuildInfo(sourceDirty: true).sourceLabel, L10n.s("Local changes"))
        XCTAssertEqual(BuildInfo(sourceDirty: false).sourceLabel, L10n.s("Clean build inputs"))
        XCTAssertEqual(BuildInfo().sourceLabel, L10n.s("Source state unavailable"))
    }

    func testReportHasOnlyAllowlistedKeysAndStableUniqueChecks() throws {
        let report = DiagnosticReport(build: BuildInfo(), macOSVersion: "/Users/private", runtimeArchitecture: "serial",
            checks: [.init(id: .hotkeys, status: .fail), .init(id: .accessibility, status: .ok),
                     .init(id: .hotkeys, status: .ok)])
        XCTAssertEqual(report.macOSVersion, "unknown")
        XCTAssertEqual(report.runtimeArchitecture, "unknown")
        XCTAssertEqual(report.checks.map(\.id), [.accessibility, .hotkeys])
        let data = try report.jsonData()
        XCTAssertEqual(data, try report.jsonData(), "Preview and save use stable bytes")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["schema_version", "build", "macos_version", "runtime_architecture", "checks", "privacy"])
        for check in try XCTUnwrap(json["checks"] as? [[String: Any]]) {
            XCTAssertEqual(Set(check.keys), ["id", "status"])
        }
    }

    func testUnsupportedManifestAndUnexpectedStringsFailClosed() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(BuildInfo.self, from: Data("{\"schema_version\":2}".utf8)))
        for value in ["0.1.0\nSECRET", "1.0 token", "../1", "", String(repeating: "1", count: 200)] {
            XCTAssertEqual(BuildInfo(appVersion: value).appVersion, "unknown")
        }
    }
}
