// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ReadingToolsNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ReadingToolsWorkspace",
            type: .dynamic,
            targets: ["ReadingToolsWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "ReadingToolsWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "ReadingToolsWorkspaceTests",
            dependencies: [
                "ReadingToolsWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
