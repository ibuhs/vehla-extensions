// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ToolboxNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "ToolboxWorkspace",
            type: .dynamic,
            targets: ["ToolboxWorkspace"]
        ),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(url: "https://github.com/wisetail/BCryptSwift.git", from: "2.0.1"),
        .package(url: "https://github.com/orlandos-nl/BSON.git", from: "8.1.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "CArgon2",
            path: "Sources/CArgon2",
            exclude: [
                "NOTICE",
                "src/blake2/blamka-round-opt.h",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("src"),
            ]
        ),
        .target(
            name: "ToolboxWorkspace",
            dependencies: [
                "CArgon2",
                .product(name: "VehlaNativeUISDK", package: "swift"),
                .product(name: "BCryptSwift", package: "BCryptSwift"),
                .product(name: "BSON", package: "BSON"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
                .product(name: "Splash", package: "Splash"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "ToolboxWorkspaceTests",
            dependencies: [
                "ToolboxWorkspace",
                .product(name: "VehlaNativeUISDK", package: "swift"),
                .product(name: "BSON", package: "BSON"),
            ]
        ),
    ]
)
