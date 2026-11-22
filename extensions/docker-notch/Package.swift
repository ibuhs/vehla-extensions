// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DockerNotch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DockerNotch", type: .dynamic, targets: ["DockerNotch"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "DockerNotch",
            dependencies: [
                .product(name: "VehlaNotchSDK", package: "swift"),
            ]
        ),
        .testTarget(name: "DockerNotchTests", dependencies: ["DockerNotch"]),
    ]
)
