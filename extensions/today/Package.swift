// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Today",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Today", type: .dynamic, targets: ["Today"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(path: "../notch-kit"),
    ],
    targets: [
        .target(name: "TodayCore"),
        .target(
            name: "Today",
            dependencies: [
                "TodayCore",
                .product(name: "VehlaNotchSDK", package: "swift"),
                .product(name: "NotchKit", package: "notch-kit"),
            ]
        ),
        .testTarget(name: "TodayCoreTests", dependencies: ["TodayCore"]),
    ]
)
