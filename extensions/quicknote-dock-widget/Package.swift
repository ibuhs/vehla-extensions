// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickNoteDockWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QuickNoteDockWidget", type: .dynamic, targets: ["QuickNoteDockWidget"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "QuickNoteDockWidget",
            dependencies: [
                .product(name: "VehlaDockWidgetSDK", package: "swift"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "QuickNoteDockWidgetTests",
            dependencies: ["QuickNoteDockWidget"],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
