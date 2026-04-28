// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "health",
    platforms: [
        .macOS(.v13),
        .iOS(.v14),
    ],
    products: [
        .library(name: "health", targets: ["health"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FlutterShim",
            dependencies: [],
            path: "Sources/Flutter"
        ),
        .target(
            name: "health",
            dependencies: [
                "FlutterShim"
            ]
        ),
        .testTarget(
            name: "healthTests",
            dependencies: ["health"],
            path: "Tests"
        ),

    ]
)
