// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HertzlyDockWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HertzlyDockWidget", type: .dynamic, targets: ["HertzlyDockWidget"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "HertzlyDockWidget",
            dependencies: [
                .product(name: "VehlaDockWidgetSDK", package: "swift"),
            ],
            path: "Sources/HertzlyDockWidget"
        ),
        .testTarget(
            name: "HertzlyDockWidgetTests",
            dependencies: ["HertzlyDockWidget"],
            path: "Tests/HertzlyDockWidgetTests"
        ),
    ]
)
