// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "health_bridge",
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(name: "health-bridge", targets: ["health_bridge"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(path: "HealthBridgeWorkoutCore")
    ],
    targets: [
        .target(
            name: "health_bridge",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(
                    name: "HealthBridgeWorkoutCore",
                    package: "HealthBridgeWorkoutCore"
                )
            ],
            path: "Sources/health",
            linkerSettings: [
                .linkedFramework("HealthKit")
            ]
        )
    ]
)
