import Foundation
import XCTest
import VehlaDockWidgetSDK
@testable import LofiDockWidget

final class ManifestContractTests: XCTestCase {
    struct Manifest: Decodable {
        let dockWidgets: [Widget]
        struct Widget: Decodable {
            let id: String
            let title: String
            let subtitle: String?
            let systemImage: String
            let preferredPopupWidth: Double
            let preferredPopupHeight: Double
            let supportedSurfaces: [String]
        }
    }
    @MainActor
    func testPluginMetadataMatchesManifestExactly() async throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: package.appendingPathComponent("extension.json")))
        let plugin = LofiDockWidgetPlugin()
        XCTAssertEqual(plugin.widgets.count, manifest.dockWidgets.count)
        let surfaces: [String: VehlaDockWidgetSurface] = ["compact": .compact, "inline": .inline, "popup": .popup]
        for widget in manifest.dockWidgets {
            let descriptor = try XCTUnwrap(plugin.widgets.first { $0.id == widget.id })
            XCTAssertEqual(descriptor.title, widget.title)
            XCTAssertEqual(descriptor.subtitle, widget.subtitle)
            XCTAssertEqual(descriptor.systemImage, widget.systemImage)
            XCTAssertEqual(descriptor.preferredPopupWidth, widget.preferredPopupWidth)
            XCTAssertEqual(descriptor.preferredPopupHeight, widget.preferredPopupHeight)
            XCTAssertEqual(Set(descriptor.supportedSurfaceValues.map(\.intValue)),
                Set(try widget.supportedSurfaces.map { try XCTUnwrap(surfaces[$0]).rawValue }))
        }
    }
}
