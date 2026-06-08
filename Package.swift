// swift-tools-version:5.10
import PackageDescription

// Week 1 foundation — SwiftPM stepping stone (builds with Command Line Tools; migrates to an
// Xcode app project once Xcode 16 is installed). Testable logic lives in BeamhopCore; the
// AppKit menu-bar shell is the Beamhop executable.
let package = Package(
    name: "Beamhop",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    ],
    targets: [
        .target(
            name: "BeamhopCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/BeamhopCore"
        ),
        .executableTarget(
            name: "Beamhop",
            dependencies: ["BeamhopCore"],
            path: "Sources/Beamhop"
        ),
        // Beamhop's own MCP server (stdio JSON-RPC). Registered with Claude Code via
        // `claude mcp add beamhop -s user -- <bin> --db <inbox.sqlite>`. Reads the DB read-only.
        .executableTarget(
            name: "BeamhopMCP",
            dependencies: ["BeamhopCore"],
            path: "Sources/BeamhopMCP"
        ),
        // XCTest-free runner so storage logic can be validated under Command Line Tools
        // (XCTest ships with full Xcode). Mirrors Tests/BeamhopCoreTests/StorageTests.swift.
        .executableTarget(
            name: "BeamhopSelfTest",
            dependencies: ["BeamhopCore"],
            path: "Sources/BeamhopSelfTest"
        ),
        .testTarget(
            name: "BeamhopCoreTests",
            dependencies: ["BeamhopCore"],
            path: "Tests/BeamhopCoreTests"
        ),
    ]
)
