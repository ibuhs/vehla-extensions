// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZLibraryNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ZLibraryWorkspace",
            type: .dynamic,
            targets: ["ZLibraryWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "ZLibraryWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "ZLibraryWorkspaceTests",
            dependencies: ["ZLibraryWorkspace"]
        ),
    ]
)
