// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ActionsHub",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ActionsHub", type: .dynamic, targets: ["ActionsHub"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(path: "../notch-kit"),
    ],
    targets: [
        .target(name: "ActionsHubCore"),
        .target(
            name: "ActionsHub",
            dependencies: [
                "ActionsHubCore",
                .product(name: "VehlaNotchSDK", package: "swift"),
                .product(name: "NotchKit", package: "notch-kit"),
            ]
        ),
        .testTarget(name: "ActionsHubCoreTests", dependencies: ["ActionsHubCore"]),
    ]
)
