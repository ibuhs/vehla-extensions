// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftHelloExtension",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "SwiftHelloExtension",
            targets: ["SwiftHelloExtension"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftHelloExtension",
            dependencies: [
                .product(
                    name: "VehlaStoreSDK",
                    package: "swift"
                ),
            ]
        ),
    ]
)
