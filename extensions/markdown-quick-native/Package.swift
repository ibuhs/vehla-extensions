// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkdownQuickNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MarkdownQuickWorkspace",
            type: .dynamic,
            targets: ["MarkdownQuickWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "MarkdownQuickWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "MarkdownQuickWorkspaceTests",
            dependencies: [
                "MarkdownQuickWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
