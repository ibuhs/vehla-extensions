// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "LofiDockWidget", platforms: [.macOS("14.2")],
    products: [.library(name: "LofiDockWidget", type: .dynamic, targets: ["LofiDockWidget"])],
    dependencies: [.package(path: "../../sdk/swift")],
    targets: [

        .target(name: "LofiDockWidget", dependencies: [.product(name: "VehlaDockWidgetSDK", package: "swift")]),
        .testTarget(name: "LofiDockWidgetTests", dependencies: ["LofiDockWidget"], resources: [.copy("Fixtures")])
    ]
)
