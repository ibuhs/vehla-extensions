// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VehlaStoreSDK",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "VehlaStoreSDK",
            targets: ["VehlaStoreSDK"]
        ),
    ],
    targets: [
        .target(name: "VehlaStoreSDK"),
        .testTarget(
            name: "VehlaStoreSDKTests",
            dependencies: ["VehlaStoreSDK"]
        ),
    ]
)
