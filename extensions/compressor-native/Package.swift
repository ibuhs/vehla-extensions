// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CompressorNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "CompressorWorkspace",
            type: .dynamic,
            targets: ["CompressorWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "CompressorWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "CompressorWorkspaceTests",
            dependencies: ["CompressorWorkspace"]
        ),
    ]
)
