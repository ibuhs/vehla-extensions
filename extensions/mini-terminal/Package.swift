// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MiniTerminal",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MiniTerminal", type: .dynamic, targets: ["MiniTerminal"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(path: "../notch-kit"),
    ],
    targets: [
        // Terminal emulator, key encoding, PTY and shell integration: no UI, testable on their own.
        // A few lines of C: forkpty() so the shell gets a real controlling terminal (Swift can't call it safely).
        .target(name: "CPty"),
        .target(name: "MiniTerminalCore", dependencies: ["CPty"]),
        .target(
            name: "MiniTerminal",
            dependencies: [
                "MiniTerminalCore",
                .product(name: "VehlaNotchSDK", package: "swift"),
                .product(name: "NotchKit", package: "notch-kit"),
            ]
        ),
        .testTarget(name: "MiniTerminalCoreTests", dependencies: ["MiniTerminalCore"]),
    ]
)
