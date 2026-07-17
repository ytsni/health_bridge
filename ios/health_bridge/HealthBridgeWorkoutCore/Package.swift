// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HealthBridgeWorkoutCore",
    platforms: [
        .iOS(.v14),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "HealthBridgeWorkoutCore",
            targets: ["HealthBridgeWorkoutCore"]
        )
    ],
    targets: [
        .target(
            name: "HealthBridgeWorkoutCore",
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        ),
        .testTarget(
            name: "HealthBridgeWorkoutCoreTests",
            dependencies: ["HealthBridgeWorkoutCore"]
        ),
    ]
)
