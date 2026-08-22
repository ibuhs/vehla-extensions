// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ListLabNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ListLabWorkspace",
            type: .dynamic,
            targets: ["ListLabWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "ListLabWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "ListLabWorkspaceTests",
            dependencies: [
                "ListLabWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
