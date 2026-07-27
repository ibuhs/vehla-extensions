// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NewsDockWidgets",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "NewsDockWidgets",
            type: .dynamic,
            targets: ["NewsDockWidgets"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
    ],
    targets: [
        .target(
            name: "NewsDockWidgets",
            dependencies: [
                .product(name: "VehlaDockWidgetSDK", package: "swift"),
            ]
        ),
    ]
)
