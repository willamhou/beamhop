import Foundation
import XCTest
@testable import BeamhopCore

final class MCPRegistrationConfigTests: XCTestCase {
    func testDesktopRegistrationCreatesBothHomesAndPreservesEachExistingConfig() throws {
        for existing in [[], [0], [1], [0, 1]] as [[Int]] {
            let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: support) }
            let urls = MCPRegistrationConfig.desktopURLs(in: support)
            for index in existing {
                try FileManager.default.createDirectory(at: urls[index].deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{\"theme\":\"variant\(index)\",\"mcpServers\":{\"other\":{\"command\":\"keep\"}}}".utf8).write(to: urls[index])
            }
            try MCPRegistrationConfig.registerDesktop(in: support, name: "beamhop", command: "/fixture/helper", arguments: ["--db", "/fixture/db"])
            for (index, url) in urls.enumerated() {
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
                let servers = try XCTUnwrap(json["mcpServers"] as? [String: [String: Any]])
                XCTAssertEqual(servers["beamhop"]?["command"] as? String, "/fixture/helper")
                XCTAssertEqual(servers["beamhop"]?["args"] as? [String], ["--db", "/fixture/db"])
                if existing.contains(index) {
                    XCTAssertEqual(json["theme"] as? String, "variant\(index)")
                    XCTAssertEqual(servers["other"]?["command"] as? String, "keep")
                }
            }
        }
    }

    func testMalformedDeploymentPreventsWritesToEitherHome() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let urls = MCPRegistrationConfig.desktopURLs(in: support)
        let original = [Data(#"{"theme":"keep"}"#.utf8), Data("invalid JSON".utf8)]
        for (url, data) in zip(urls, original) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        XCTAssertThrowsError(try MCPRegistrationConfig.registerDesktop(in: support, name: "beamhop", command: "helper", arguments: []))
        for (url, data) in zip(urls, original) { XCTAssertEqual(try Data(contentsOf: url), data) }
    }

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
