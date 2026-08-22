// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypePolishNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "TypePolishWorkspace",
            type: .dynamic,
            targets: ["TypePolishWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "TypePolishWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "TypePolishWorkspaceTests",
            dependencies: [
                "TypePolishWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
