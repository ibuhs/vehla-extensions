// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftSDKLab",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftSDKLabExtension",
            dependencies: [
                .product(
                    name: "VehlaStoreSDK",
                    package: "swift"
                ),
            ]
        ),
    ]
)
