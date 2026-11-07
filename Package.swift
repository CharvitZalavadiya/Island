// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Island",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Island", targets: ["Island"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .target(name: "IslandUI", dependencies: ["IslandCore"]),
        .executableTarget(name: "Island", dependencies: ["IslandUI"]),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
        .testTarget(name: "IslandUITests", dependencies: ["IslandUI", "IslandCore"]),
    ],
    swiftLanguageModes: [.v5]
)
