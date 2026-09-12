import Foundation
import XCTest
@testable import BeamhopCore

final class PromptRendererTests: XCTestCase {
    private let capture = Capture(
        id: "cap_render",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        source: .browser,
        appBundleID: "com.apple.Safari",
        appName: "Safari",
        windowTitle: "Fix queue race",
        url: URL(string: "https://example.com/pull/1"),
        selectedText: "let next = queue.first",
        extractedBody: "The full pull request body.",
        screenshotPath: "screenshots/cap_render.png",
        userNote: "Find correctness issues",
        domainHint: "github.pr",
        provenance: CaptureProvenance(
            processID: 7,
            appVersion: "17.6",
            operatingSystemVersion: "15.6",
            beamhopVersion: "0.1.0",
            captureMethod: .browserExtension,
            isPrivate: false,
            isTruncated: true,
            captureDurationMilliseconds: 24
        )
    )

    func testClaudeCodeRendererUsesReferenceInsteadOfDumpingBody() {
        let rendered = ClaudeCodeRenderer().render(capture, userNote: nil)
        XCTAssertTrue(rendered.contains("fetch_capture"))
        XCTAssertTrue(rendered.contains("cap_render"))
        XCTAssertTrue(rendered.contains("Find correctness issues"))
        XCTAssertFalse(rendered.contains("The full pull request body"))
    }

    func testSelfContainedRendererIncludesContentAndInspectableProvenance() {
        let rendered = ChatGPTDesktopRenderer().render(capture, userNote: "Explain the race")
        XCTAssertTrue(rendered.contains("Source: Safari · https://example.com/pull/1"))
        XCTAssertTrue(rendered.contains("<selected>\nlet next = queue.first\n</selected>"))
        XCTAssertTrue(rendered.contains("<body>\nThe full pull request body.\n</body>"))
        XCTAssertTrue(rendered.contains("Explain the race"))
        XCTAssertFalse(rendered.contains("Find correctness issues"))
        XCTAssertTrue(rendered.contains("method=browser_extension"))
        XCTAssertTrue(rendered.contains("truncated=true"))
    }
}
