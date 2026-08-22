// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LinkLensNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "LinkLensWorkspace",
            type: .dynamic,
            targets: ["LinkLensWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "LinkLensWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "LinkLensWorkspaceTests",
            dependencies: [
                "LinkLensWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
