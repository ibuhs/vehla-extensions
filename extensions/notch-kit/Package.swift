// swift-tools-version: 6.0

import PackageDescription

/// Shared design kit for Vehla Notch extensions: one look, one set of controls.
let package = Package(
    name: "notch-kit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchKit", targets: ["NotchKit"]),
    ],
    targets: [
        .target(name: "NotchKit"),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
    ]
)
