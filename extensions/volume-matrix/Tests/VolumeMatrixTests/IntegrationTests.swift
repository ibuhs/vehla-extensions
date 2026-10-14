import XCTest
@testable import VolumeMatrix

final class IntegrationTests: XCTestCase {
    func testLiveInventoryAndDriverCounters() throws {
        guard ProcessInfo.processInfo.environment["VEHLA_VOLUME_INTEGRATION"] == "1" else { throw XCTSkip("Opt-in read-only host inventory test") }
        let inventory = try DiskInventoryReader.read()
        XCTAssertTrue(inventory.volumes.contains { $0.mountPoint == "/" && $0.isProtected })
        XCTAssertFalse(inventory.volumes.contains { $0.mounted && $0.name.isEmpty })
        XCTAssertTrue(inventory.containers.allSatisfy { $0.capacity > 0 && $0.free >= 0 && $0.free <= $0.capacity })
        let counters = DiskActivityReader.read()
        XCTAssertFalse(counters.isEmpty)
        XCTAssertTrue(counters.keys.allSatisfy { $0.hasPrefix("disk") })
        print("Live inventory: \(inventory.volumes.count) volumes, \(inventory.containers.count) APFS containers, \(counters.count) physical-device counters.")
    }
    func testMountUnmountEjectDisposableDiskImage() async throws {
        guard ProcessInfo.processInfo.environment["VEHLA_VOLUME_OPERATIONS"] == "1" else { throw XCTSkip("Opt-in operations on a disposable disk image") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vehla-volume-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = directory.appendingPathComponent("test.dmg").path
        _ = try command(["create", "-size", "128m", "-fs", "APFS", "-volname", "Vehla Volume Test", image])
        let data = try command(["attach", "-nobrowse", "-plist", image])
        let plist = try DiskInventoryReader.plist(data)
        let entities = try XCTUnwrap(plist["system-entities"] as? [[String: Any]])
        let node = try XCTUnwrap(entities.first { $0["mount-point"] != nil })
        let device = try XCTUnwrap(node["dev-entry"] as? String)
        let id = String(device.dropFirst("/dev/".count))
        defer { _ = try? command(["detach", device]) }
        var inventory = try DiskInventoryReader.read()
        let initial = try XCTUnwrap(inventory.volumes.first { $0.id == id })
        XCTAssertEqual(initial.name, "Vehla Volume Test")
        XCTAssertFalse(initial.isInternal); XCTAssertFalse(initial.isProtected)
        try await DiskActions.perform(.unmount, volume: initial)
        inventory = try DiskInventoryReader.read()
        let unmounted = try XCTUnwrap(inventory.volumes.first { $0.id == id })
        XCTAssertFalse(unmounted.mounted)
        try await DiskActions.perform(.mount, volume: unmounted)
        inventory = try DiskInventoryReader.read()
        let mounted = try XCTUnwrap(inventory.volumes.first { $0.id == id })
        XCTAssertTrue(mounted.mounted)
        try await DiskActions.perform(.eject, volume: mounted)
        inventory = try DiskInventoryReader.read()
        XCTAssertFalse(inventory.volumes.contains { $0.id == id })
    }
    private func command(_ arguments: [String]) throws -> Data {
        let process = Process(); let output = Pipe(); let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments; process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DiskError.message("Disposable image setup failed.") }
        return data
    }
}
