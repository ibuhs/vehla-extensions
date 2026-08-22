// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DataExtractorNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "DataExtractorWorkspace",
            type: .dynamic,
            targets: ["DataExtractorWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "DataExtractorWorkspace",
            dependencies: [
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
        .testTarget(
            name: "DataExtractorWorkspaceTests",
            dependencies: [
                "DataExtractorWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
            ]
        ),
    ]
)
