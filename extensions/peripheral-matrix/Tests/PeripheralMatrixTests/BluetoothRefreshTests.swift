import CoreBluetooth
import XCTest
import VehlaDockWidgetSDK
@testable import PeripheralMatrix

final class BluetoothRefreshTests: XCTestCase {
    func testConnectedDeviceWithMissingServiceOrCharacteristicIsDiscovered() {
        let now = Date()
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connected, hasService: false, hasReadableLevel: false, lastRead: nil, force: false, now: now), .discoverServices)
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connected, hasService: true, hasReadableLevel: false, lastRead: nil, force: true, now: now), .discoverCharacteristics)
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .disconnected, hasService: false, hasReadableLevel: false, lastRead: nil, force: true, now: now), .connect)
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connecting, hasService: false, hasReadableLevel: false, lastRead: nil, force: true, now: now), .wait)
    }
    func testManualRefreshBypassesReadThrottleButPeriodicRefreshDoesNot() {
        let now = Date()
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connected, hasService: true, hasReadableLevel: true, lastRead: now, force: false, now: now), .none)
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connected, hasService: true, hasReadableLevel: true, lastRead: now, force: true, now: now), .read)
        XCTAssertEqual(BatteryRefreshPolicy.action(state: .connected, hasService: true, hasReadableLevel: true, lastRead: nil, force: false, now: now), .read)
    }
    @MainActor func testTransientOffAndCancelledManagerNeverPublishOffWarning() async {
        var off = true
        var warnings = 0
        let recovered = BluetoothStateWarning.schedule(delay: .milliseconds(10), isStillOff: { off }, report: { warnings += 1 })
        off = false
        await recovered.value
        XCTAssertEqual(warnings, 0)
        let cancelled = BluetoothStateWarning.schedule(delay: .milliseconds(10), isStillOff: { true }, report: { warnings += 1 })
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(warnings, 0)
        let sustained = BluetoothStateWarning.schedule(delay: .milliseconds(10), isStillOff: { true }, report: { warnings += 1 })
        await sustained.value
        XCTAssertEqual(warnings, 1)
    }
    @MainActor func testBluetoothRecoveryClearsOnlyItsOwnWarning() {
        let bluetooth = BatteryStub()
        let model = PeripheralMatrixModel(readRegistry: { [] }, bluetooth: bluetooth)
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .white, primaryTextColor: .white, secondaryTextColor: .gray, surfaceColor: .black)
        model.configure(.init(packageID: "test", widgetID: "peripheral-matrix", dataDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        defer { model.close() }
        model.error = "QMK connection failed"
        bluetooth.onError?("Bluetooth is turned off.")
        XCTAssertNotNil(model.bluetoothError)
        bluetooth.onError?(nil) // The manager recovered to poweredOn.
        XCTAssertNil(model.bluetoothError)
        XCTAssertEqual(model.error, "QMK connection failed")
        bluetooth.onError?("Bluetooth access denied")
        model.setBluetooth(false)
        XCTAssertNil(model.bluetoothError)
        XCTAssertEqual(model.error, "QMK connection failed")
    }
    @MainActor func testRefreshGetsMissingBatteryWithoutTogglingLE() async {
        let bluetooth = BatteryStub()
        let model = PeripheralMatrixModel(readRegistry: { [.init(id: "mouse", name: "Mouse", transport: "Bluetooth", kind: "Mouse", battery: nil)] }, bluetooth: bluetooth)
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .white, primaryTextColor: .white, secondaryTextColor: .gray, surfaceColor: .black)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        model.configure(.init(packageID: "test", widgetID: "peripheral-matrix", dataDirectory: directory, theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        model.setBluetooth(true)
        await model.waitForRegistryRefresh()
        XCTAssertNil(model.lowestBattery)
        model.refresh()
        await model.waitForRegistryRefresh()
        XCTAssertEqual(model.lowestBattery, 15)
        XCTAssertEqual(bluetooth.starts, 1)
        XCTAssertEqual(bluetooth.stops, 0)
        XCTAssertTrue(bluetooth.forced)
        model.close()
    }
}
@MainActor private final class BatteryStub: BluetoothBatteryControlling {
    var enabled = false
    var snapshots: [UUID: PeripheralSnapshot] = [:]
    var onChange: (() -> Void)?
    var onError: ((String?) -> Void)?
    var starts = 0, stops = 0
    var forced = false
    func start() { enabled = true; starts += 1 }
    func stop() { enabled = false; stops += 1 }
    func refresh(force: Bool) {
        forced = force
        if force { snapshots[UUID()] = .init(id: "battery", name: "Mouse", transport: "Bluetooth LE", kind: "Peripheral", battery: 15); onChange?() }
    }
}
