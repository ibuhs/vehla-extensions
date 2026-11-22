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
        // Static on purpose: compiled into the extension's bundle, so Vehla embeds no framework for it.
        .library(
            name: "VehlaNotchSDK",
            targets: ["VehlaNotchSDK"]
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
        .target(name: "VehlaNotchSDK"),
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
            name: "VehlaNotchSDKTests",
            dependencies: ["VehlaNotchSDK"]
        ),
        .testTarget(
            name: "VehlaDockWidgetSDKTests",
            dependencies: ["VehlaDockWidgetSDK"]
        ),
    ]
)
