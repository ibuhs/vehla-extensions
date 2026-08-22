// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NumberCrunchNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "NumberCrunchWorkspace",
            type: .dynamic,
            targets: ["NumberCrunchWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "NumberCrunchWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "NumberCrunchWorkspaceTests",
            dependencies: [
                "NumberCrunchWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
