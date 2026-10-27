import XCTest
@testable import PeripheralMatrix

final class InventoryTests: XCTestCase {
    @MainActor
    func testDockIconFollowsLowestBatteryAcrossDeviceKinds() {
        let model = PeripheralMatrixModel(readRegistry: { [] })
        func device(_ id: String, _ kind: String, _ battery: Int?) -> PeripheralSnapshot {
            .init(id: id, name: id, transport: "Bluetooth", kind: kind, battery: battery)
        }
        model.devices = [device("mouse", "Mouse", 50), device("keyboard", "Keyboard", 56)]
        XCTAssertEqual(model.dockIcon, "computermouse.fill")
        XCTAssertEqual(model.lowestBattery, 50)
        model.devices = [device("mouse", "Mouse", 56), device("keyboard", "Keyboard", 50)]
        XCTAssertEqual(model.dockIcon, "keyboard")
        model.devices.append(device("airpods", "Headphones", 20))
        XCTAssertEqual(model.dockIcon, "headphones")
        XCTAssertEqual(model.lowestBattery, 20)
    }

    @MainActor
    func testLowestPeripheralIgnoresUnknownAndKeepsTiesStable() {
        let model = PeripheralMatrixModel(readRegistry: { [] })
        let mouse = PeripheralSnapshot(id: "a", name: "Mouse", transport: "Bluetooth", kind: "Mouse", battery: 50)
        let keyboard = PeripheralSnapshot(id: "b", name: "Keyboard", transport: "Bluetooth", kind: "Keyboard", battery: 50)
        let unknown = PeripheralSnapshot(id: "c", name: "Unknown", transport: "Bluetooth", kind: "Headphones", battery: nil)
        model.devices = [keyboard, unknown, mouse]
        XCTAssertEqual(model.lowestPeripheral?.id, mouse.id)
        model.devices.reverse()
        XCTAssertEqual(model.lowestPeripheral?.id, mouse.id)
        model.devices = [unknown]
        XCTAssertNil(model.lowestBattery)
        XCTAssertEqual(model.dockIcon, "keyboard")
    }
    func testMouseBatteryServiceMergesIntoMouseRow() {
        let mouse = PeripheralSnapshot(id: "hid.mouse", name: "MX Master 3S", transport: "Bluetooth Low Energy", kind: "Mouse", battery: nil)
        let ble = PeripheralSnapshot(id: "ble.mouse", name: "MX Master 3S", transport: "Bluetooth LE", kind: "Peripheral", battery: 15)
        let rows = PeripheralInventory.merge([mouse], batteries: [ble])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, mouse.id)
        XCTAssertEqual(rows.first?.icon, "computermouse.fill")
        XCTAssertEqual(rows.first?.batteryText, "15%")
    }

    func testAmbiguousNamesRemainSeparate() {
        let mice = ["a", "b"].map { PeripheralSnapshot(id: $0, name: "Mouse", transport: "Bluetooth", kind: "Mouse", battery: nil) }
        let ble = PeripheralSnapshot(id: "ble", name: "Mouse", transport: "Bluetooth LE", kind: "Peripheral", battery: 15)
        XCTAssertEqual(PeripheralInventory.merge(mice, batteries: [ble]).count, 3)
        XCTAssertEqual(ble.icon, "battery.100percent")
    }

    func testConnectedAirPodsMergeCaseAndEarbudReportsAndExcludeDisconnected() throws {
        let report = #"{"SPBluetoothDataType":[{"device_connected":[{"AirPods Pro":{"device_batteryLevelCase":"91%"}},{"AirPods Pro":{"device_minorType":"Headphones","device_batteryLevelLeft":"80%","device_batteryLevelRight":"80%"}}],"device_not_connected":[{"Old AirPods":{"device_batteryLevelLeft":"100%"}}]}]}"#
        let rows = ConnectedHeadphones.parse(Data(report.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.battery, 80)
        XCTAssertEqual(rows.first?.batteryText, "L 80% · R 80% · Case 91%")
        XCTAssertEqual(rows.first?.transport, "Bluetooth · Connected")
        XCTAssertEqual(rows.first?.icon, "headphones")
    }

    func testInvalidAirPodsPercentIsUnknown() {
        let report = #"{"device_connected":[{"AirPods":{"device_batteryLevelLeft":"255%","device_batteryLevelCase":"unknown"}}]}"#
        let rows = ConnectedHeadphones.parse(Data(report.utf8))
        XCTAssertNil(rows.first?.battery)
        XCTAssertEqual(rows.first?.batteryText, "Unknown")
    }
}
