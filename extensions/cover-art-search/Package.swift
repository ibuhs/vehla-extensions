// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CoverArtSearchNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "CoverArtSearchWorkspace",
            type: .dynamic,
            targets: ["CoverArtSearchWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "CoverArtSearchWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "CoverArtSearchWorkspaceTests",
            dependencies: ["CoverArtSearchWorkspace"]
        ),
    ]
)
