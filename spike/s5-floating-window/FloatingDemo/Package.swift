// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "FloatingDemo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "FloatingDemo", path: "Sources/FloatingDemo")
    ]
)
