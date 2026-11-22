// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WallhavenNotch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WallhavenNotch", type: .dynamic, targets: ["WallhavenNotch"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "WallhavenNotch",
            dependencies: [
                .product(name: "VehlaNotchSDK", package: "swift"),
            ]
        ),
    ]
)
