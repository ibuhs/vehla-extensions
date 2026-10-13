import AppKit
import XCTest
import VehlaDockWidgetSDK
@testable import PeripheralMatrix

final class QMKHardwareTests: XCTestCase {
    @MainActor func testLiveReadOnlyVIALoad() async throws {
        guard ProcessInfo.processInfo.environment["VEHLA_QMK_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in read-only VIA check on the connected K10 Pro") }
        _ = NSApplication.shared
        let model = PeripheralMatrixModel(readRegistry: { [] })
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .white, primaryTextColor: .white, secondaryTextColor: .gray, surfaceColor: .black)
        model.configure(.init(packageID: "test", widgetID: "peripheral-matrix", dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        model.start(); model.setBridge(true)
        defer { model.close() }
        for _ in 0..<100 where model.layers.allSatisfy({ $0.keymapProfile == nil }) { try await Task.sleep(for: .milliseconds(20)) }
        guard let keyboard = model.layers.first(where: { $0.keymapProfile != nil }) else { throw XCTSkip("K10 Pro ANSI White is not connected by USB") }
        let session = VIAKeymapSession(endpoint: keyboard, profile: .k10ProANSIWhite)
        let snapshot = try await session.load()
        XCTAssertEqual(snapshot.protocolVersion, 12)
        XCTAssertEqual(snapshot.layers, 4)
        XCTAssertEqual(snapshot.keycodes.count, 504)
        XCTAssertLessThanOrEqual(snapshot.macroBytes.count, 8192)
        XCTAssertFalse(keyboard.editingKeymap)
        // No apply call and no macro/keymap data printed or exported.
    }
}
