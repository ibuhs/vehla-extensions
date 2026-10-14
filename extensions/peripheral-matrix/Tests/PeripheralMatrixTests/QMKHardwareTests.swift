import AppKit
import XCTest
import VehlaDockWidgetSDK
@testable import PeripheralMatrix

final class QMKHardwareTests: XCTestCase {
    @MainActor func testProgrammingWindowAutomaticallyLoadsConnectedKeyboardReadOnly() async throws {
        guard ProcessInfo.processInfo.environment["VEHLA_QMK_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in read-only VIA check on the connected K10 Pro") }
        _ = NSApplication.shared
        let model = PeripheralMatrixModel(readRegistry: { [] })
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .white, primaryTextColor: .white, secondaryTextColor: .gray, surfaceColor: .black)
        model.configure(.init(packageID: "test", widgetID: "peripheral-matrix", dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        model.start(); model.openProgramming()
        defer { model.close() }
        for _ in 0..<100 where model.layers.allSatisfy({ $0.keymapProfile == nil }) { try await Task.sleep(for: .milliseconds(20)) }
        guard let keyboard = model.layers.first(where: { $0.keymapProfile != nil }) else { throw XCTSkip("K10 Pro ANSI White is not connected by USB") }
        model.hide() // The separate programming window must keep discovery alive.
        for _ in 0..<100 where !model.editor.busy && model.editor.baseline == nil { try await Task.sleep(for: .milliseconds(20)) }
        await model.editor.waitForOperation()
        let snapshot = try XCTUnwrap(model.editor.baseline, model.editor.status ?? "Automatic load did not complete")
        XCTAssertTrue(model.bridgeEnabled)
        XCTAssertEqual(model.editorConnectionID, keyboard.id)
        XCTAssertTrue(model.editor.changes.isEmpty)
        XCTAssertFalse(model.editor.needsReload)
        XCTAssertEqual(snapshot.protocolVersion, 12)
        XCTAssertEqual(snapshot.layers, 4)
        XCTAssertEqual(snapshot.keycodes.count, keyboard.keymapProfile?.totalKeys)
        XCTAssertLessThanOrEqual(snapshot.macroBytes.count, 8192)
        XCTAssertFalse(keyboard.editingKeymap)
        // No apply call and no macro/keymap data printed or exported.
    }
}
