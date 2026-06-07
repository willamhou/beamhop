// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HelloServer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HelloServer", path: "Sources/HelloServer")
    ]
)
