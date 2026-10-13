import XCTest
@testable import PeripheralMatrix
final class PeripheralMatrixTests: XCTestCase {
    func testLayerLabelsDescribeExistingFirmware() {
        XCTAssertEqual((0..<4).map { LayerProtocol.defaultName(layer: UInt8($0), vendor: 0x3434, product: 0x02a3) },
                       ["Mac", "Mac Fn", "Windows", "Windows Fn"])
        XCTAssertEqual(LayerProtocol.defaultName(layer: 1, vendor: 0, product: 0), "Layer 1")
        XCTAssertEqual(LayerProtocol.defaultName(layer: 4, vendor: 0x3434, product: 0x02a3), "Layer 4")
    }
    func testBatteryIsNotInventedOrClamped() {
        XCTAssertNil(PeripheralSnapshot.batteryPercent(nil))
        XCTAssertNil(PeripheralSnapshot.batteryPercent(-1))
        XCTAssertNil(PeripheralSnapshot.batteryPercent(255))
        XCTAssertEqual(PeripheralSnapshot.batteryPercent(0), 0)
        XCTAssertEqual(PeripheralSnapshot.batteryPercent(100), 100)
    }
    func testQueryPacketAndLayerBounds() {
        let query = LayerProtocol.query()
        XCTAssertEqual(query.count, 32)
        XCTAssertEqual(Array(query.prefix(6)), [0x56, 0x48, 0x4c, 0x41, 1, 1])
        XCTAssertNil(LayerProtocol.set(layer: 0, count: 0))
        XCTAssertNil(LayerProtocol.set(layer: 3, count: 3))
        XCTAssertEqual(LayerProtocol.set(layer: 2, count: 3)?[6], 2)
    }
    func testOnlyConfirmedFirmwareResponsesAreAccepted() {
        var packet = LayerProtocol.query()
        XCTAssertNil(LayerProtocol.decode(packet))
        packet[5] = 0x81; packet[6] = 1; packet[7] = 3
        XCTAssertEqual(LayerProtocol.decode(packet), .init(active: 1, count: 3))
        packet[5] = 0x82
        XCTAssertEqual(LayerProtocol.decode(packet)?.active, 1)
        packet[8] = 1; XCTAssertNil(LayerProtocol.decode(packet)); packet[8] = 0
        packet[7] = 255; XCTAssertNil(LayerProtocol.decode(packet)); packet[7] = 3
        packet[6] = 3; XCTAssertNil(LayerProtocol.decode(packet)); packet[6] = 1
        packet[4] = 2; XCTAssertNil(LayerProtocol.decode(packet)); packet[4] = 1
        packet[0] = 0; XCTAssertNil(LayerProtocol.decode(packet))
        XCTAssertNil(LayerProtocol.decode(Array(packet.prefix(9))))
    }
}
