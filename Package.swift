// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = [
    .library(name: "BeamhopCore", targets: ["BeamhopCore"]),
    .executable(name: "beamhop-mcp", targets: ["BeamhopMCP"]),
    .executable(name: "beamhop-native-host", targets: ["BeamhopNativeHost"])
]

var targets: [Target] = [
    .target(
        name: "BeamhopCore",
        linkerSettings: [
            .linkedLibrary("sqlite3")
        ]
    ),
    .executableTarget(
        name: "BeamhopMCP",
        dependencies: ["BeamhopCore"]
    ),
    .executableTarget(
        name: "BeamhopNativeHost",
        exclude: ["README.md", "install-manifest.sh"]
    ),
    .testTarget(
        name: "BeamhopCoreTests",
        dependencies: ["BeamhopCore"]
    )
]

#if os(macOS)
products.append(.executable(name: "Beamhop", targets: ["BeamhopApp"]))
targets.append(
    .executableTarget(
        name: "BeamhopApp",
        dependencies: ["BeamhopCore"],
        resources: [.copy("Resources")]
    )
)
#endif

let package = Package(
    name: "Beamhop",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
