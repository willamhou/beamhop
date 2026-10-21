import Foundation
import XCTest
@testable import BeamhopCore

final class MCPRegistrationConfigTests: XCTestCase {
    func testMergePreservesUnrelatedConfigurationAndServers() throws {
        let original = Data(#"{"theme":"dark","mcpServers":{"other":{"command":"other","env":{"TOKEN":"fixture"}}}}"#.utf8)
        let data = try MCPRegistrationConfig.updating(original, name: "beamhop", command: "/test/helper", arguments: ["--db", "/test/db"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["theme"] as? String, "dark")
        let servers = try XCTUnwrap(json["mcpServers"] as? [String: [String: Any]])
        XCTAssertEqual(servers["other"]?["command"] as? String, "other")
        XCTAssertEqual((servers["other"]?["env"] as? [String: String])?["TOKEN"], "fixture")
        XCTAssertEqual(servers["beamhop"]?["args"] as? [String], ["--db", "/test/db"])
    }

    func testMalformedExistingConfigIsNotReplaced() {
        for text in ["not JSON", "[]", #"{"mcpServers":null}"#, #"{"mcpServers":[]}"#, #"{"mcpServers":"private"}"#] {
            XCTAssertThrowsError(try MCPRegistrationConfig.updating(Data(text.utf8), name: "beamhop", command: "helper", arguments: []))
        }
    }

    func testNewDocumentAndExistingEntryUpdate() throws {
        let first = try MCPRegistrationConfig.updating(nil, name: "beamhop", command: "old", arguments: [])
        let second = try MCPRegistrationConfig.updating(first, name: "beamhop", command: "new", arguments: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: second) as? [String: Any])
        XCTAssertEqual((json["mcpServers"] as? [String: [String: Any]])?["beamhop"]?["command"] as? String, "new")
    }
}
