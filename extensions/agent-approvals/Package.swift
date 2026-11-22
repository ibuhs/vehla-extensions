// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentApprovals",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentApprovals", type: .dynamic, targets: ["AgentApprovals"]),
    ],
    dependencies: [
        .package(path: "../../sdk/swift"),
        .package(path: "../notch-kit"),
    ],
    targets: [
        // Protocol, risk scoring and session tracking: no UI, fully testable.
        .target(name: "AgentApprovalsCore"),
        .target(
            name: "AgentApprovals",
            dependencies: [
                "AgentApprovalsCore",
                .product(name: "VehlaNotchSDK", package: "swift"),
                .product(name: "NotchKit", package: "notch-kit"),
            ]
        ),
        .testTarget(name: "AgentApprovalsCoreTests", dependencies: ["AgentApprovalsCore"]),
    ]
)
