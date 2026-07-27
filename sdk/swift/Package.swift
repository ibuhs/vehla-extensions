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
        .library(
            name: "VehlaNativeUISDK",
            type: .dynamic,
            targets: ["VehlaNativeUISDK"]
        ),
        .library(
            name: "VehlaDockWidgetSDK",
            type: .dynamic,
            targets: ["VehlaDockWidgetSDK"]
        ),
        .executable(
            name: "vehla-swift",
            targets: ["VehlaSwiftCLI"]
        ),
    ],
    targets: [
        .target(name: "VehlaStoreSDK"),
        .target(name: "VehlaNativeUISDK"),
        .target(name: "VehlaDockWidgetSDK"),
        .executableTarget(
            name: "VehlaSwiftCLI",
            dependencies: ["VehlaStoreSDK"]
        ),
        .testTarget(
            name: "VehlaStoreSDKTests",
            dependencies: ["VehlaStoreSDK"]
        ),
        .testTarget(
            name: "VehlaNativeUISDKTests",
            dependencies: ["VehlaNativeUISDK"]
        ),
        .testTarget(
            name: "VehlaDockWidgetSDKTests",
            dependencies: ["VehlaDockWidgetSDK"]
        ),
    ]
)
