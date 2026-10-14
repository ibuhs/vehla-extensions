// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VolumeMatrix", platforms: [.macOS("14.2")],
    products: [.library(name: "VolumeMatrix", type: .dynamic, targets: ["VolumeMatrix"])],
    dependencies: [.package(path: "../../sdk/swift")],
    targets: [

        .target(name: "VolumeMatrix", dependencies: [.product(name: "VehlaDockWidgetSDK", package: "swift")]),
        .testTarget(name: "VolumeMatrixTests", dependencies: ["VolumeMatrix"])
    ]
)
