// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NotchLab",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchLab", type: .dynamic, targets: ["NotchLab"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "NotchLab",
            dependencies: [
                .product(name: "VehlaNotchSDK", package: "swift"),
            ]
        ),
    ]
)
