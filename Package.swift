// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntigravitySwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AntigravitySwitcherCore", targets: ["AntigravitySwitcherCore"]),
        .executable(name: "agswitch", targets: ["agswitch"]),
        .executable(name: "AntigravitySwitcherUI", targets: ["AntigravitySwitcherUI"])
    ],
    targets: [
        .target(
            name: "AntigravitySwitcherCore",
            resources: [.process("Resources")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "agswitch",
            dependencies: ["AntigravitySwitcherCore"]
        ),
        .executableTarget(
            name: "AntigravitySwitcherUI",
            dependencies: ["AntigravitySwitcherCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AntigravitySwitcherCoreTests",
            dependencies: ["AntigravitySwitcherCore"]
        )
    ]
)
