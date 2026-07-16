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
        .executable(
            name: "vehla-swift",
            targets: ["VehlaSwiftCLI"]
        ),
    ],
    targets: [
        .target(name: "VehlaStoreSDK"),
        .executableTarget(
            name: "VehlaSwiftCLI",
            dependencies: ["VehlaStoreSDK"]
        ),
        .testTarget(
            name: "VehlaStoreSDKTests",
            dependencies: ["VehlaStoreSDK"]
        ),
    ]
)
