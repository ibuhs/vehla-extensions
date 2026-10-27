import Combine
import XCTest
@testable import PeripheralMatrix

private actor RegistryStub {
    var reads = 0
    func read() -> [PeripheralSnapshot] {
        reads += 1
        return [.init(id: "keyboard", name: "Keyboard", transport: "Bluetooth", kind: "Keyboard", battery: 80)]
    }
}

final class RefreshTests: XCTestCase {
    @MainActor
    func testCoalescesConcurrentScansAndDoesNotPublishUnchangedDevices() async {
        let registry = RegistryStub()
        let model = PeripheralMatrixModel(readRegistry: { await registry.read() })
        var publications = 0
        let subscription = model.$devices.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel(); model.close() }
        for _ in 0..<100 { model.refresh() }
        await model.waitForRegistryRefresh()
        let firstReads = await registry.reads
        XCTAssertEqual(firstReads, 1)
        XCTAssertEqual(publications, 1)
        model.refresh()
        await model.waitForRegistryRefresh()
        let secondReads = await registry.reads
        XCTAssertEqual(secondReads, 2)
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(model.lowestBattery, 80)
    }
}
