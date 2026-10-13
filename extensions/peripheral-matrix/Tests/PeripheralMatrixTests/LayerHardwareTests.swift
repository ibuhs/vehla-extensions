import AppKit
import IOKit.hid
import XCTest
import VehlaDockWidgetSDK
@testable import PeripheralMatrix

final class LayerHardwareTests: XCTestCase {
    // Explicitly enabled on a connected K10 Pro running the bridge. Query-only:
    // this test never switches layers, changes mappings or writes EEPROM.
    @MainActor
    func testLiveHandshakeWhilePopupTracksEvents() throws {
        guard ProcessInfo.processInfo.environment["VEHLA_HID_INTEGRATION"] == "1" else {
            throw XCTSkip("Set VEHLA_HID_INTEGRATION=1 with the bridged K10 Pro connected by USB")
        }
        _ = NSApplication.shared
        let mode = CFRunLoopMode(rawValue: RunLoop.Mode.eventTracking.rawValue as CFString)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), mode)
        let model = PeripheralMatrixModel(readRegistry: { [] })
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .systemTeal,
            primaryTextColor: .white, secondaryTextColor: .lightGray, surfaceColor: .windowBackgroundColor)
        model.configure(VehlaDockWidgetContext(packageID: "test", widgetID: "peripheral-matrix",
            dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        model.start()
        defer { model.close() }
        model.setBridge(true)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !model.layers.contains(where: { $0.state != nil }) {
            CFRunLoopRunInMode(mode, 0.05, false)
        }
        let connection = try XCTUnwrap(model.layers.first(where: {
            (IOHIDDeviceGetProperty($0.device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.uint32Value == 0x3434 &&
            (IOHIDDeviceGetProperty($0.device, kIOHIDProductIDKey as CFString) as? NSNumber)?.uint32Value == 0x02a3
        }), "No K10 Pro Raw HID interface; \(model.error ?? "no error")")
        let state = try XCTUnwrap(connection.state, "Popup did not receive the live VHLA reply; \(model.error ?? "no HID error")")
        XCTAssertEqual(state.count, 4)
        XCTAssertLessThan(state.active, 4)
        XCTAssertEqual(model.name(connection, layer: 0), "Mac")
        for _ in 0..<3 {
            model.testBridge()
            let retryDeadline = Date().addingTimeInterval(3)
            while Date() < retryDeadline && !model.layers.contains(where: { $0.state != nil }) {
                CFRunLoopRunInMode(mode, 0.05, false)
            }
            XCTAssertEqual(model.layers.first?.state?.count, 4, "Test bridge did not confirm a fresh connection: \(model.bridgeTestResult ?? "no result")")
            XCTAssertTrue(model.bridgeTestResult?.contains("Confirmed 4 layers") == true,
                          "Test bridge did not publish the successful diagnostic result")
        }
        XCTAssertGreaterThanOrEqual(connection.reportsReceived, 4, "Report delivery stopped after the initial handshake")
    }
}
