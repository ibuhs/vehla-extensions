// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Wellbeing",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Wellbeing", type: .dynamic, targets: ["Wellbeing"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(path: "../notch-kit"),
    ],
    targets: [
        .target(name: "WellbeingCore"),
        .target(
            name: "Wellbeing",
            dependencies: [
                "WellbeingCore",
                .product(name: "VehlaNotchSDK", package: "swift"),
                .product(name: "NotchKit", package: "notch-kit"),
            ]
        ),
        .testTarget(name: "WellbeingCoreTests", dependencies: ["WellbeingCore"]),
    ]
)
