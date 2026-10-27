// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "PeripheralMatrix", platforms: [.macOS("14.2")],
    products: [.library(name: "PeripheralMatrix", type: .dynamic, targets: ["PeripheralMatrix"])],
    dependencies: [.package(path: "../../sdk/swift")],
    targets: [

        .target(name: "PeripheralMatrix", dependencies: [.product(name: "VehlaDockWidgetSDK", package: "swift")], resources: [.process("Resources")]),
        .testTarget(name: "PeripheralMatrixTests", dependencies: ["PeripheralMatrix"])
    ]
)
