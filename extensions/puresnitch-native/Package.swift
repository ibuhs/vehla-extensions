// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PureSnitchNative",
    platforms: [.macOS(.v14)],
    products: [.library(name: "PureSnitchWorkspace", type: .dynamic, targets: ["PureSnitchWorkspace"])],
    dependencies: [.package(path: "../../sdk/swift")],
    targets: [
        .target(
            name: "PureSnitchWorkspace",
            dependencies: [.product(name: "VehlaNativeUISDK", package: "swift")],
            path: "Sources",
            exclude: ["Helper", "Companion"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(name: "PureSnitchWorkspaceTests", dependencies: ["PureSnitchWorkspace"], path: "WorkspaceTests"),
    ],
    swiftLanguageModes: [.v5]
)
