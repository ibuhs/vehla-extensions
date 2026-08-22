// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CaptureHubNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "CaptureHubWorkspace",
            type: .dynamic,
            targets: ["CaptureHubWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "CaptureHubWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "CaptureHubWorkspaceTests",
            dependencies: [
                "CaptureHubWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
