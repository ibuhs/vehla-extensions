import XCTest
@testable import VolumeMatrix

final class VolumeTests: XCTestCase {
    func testAPFSSharedSpaceSnapshotAndBootProtection() throws {
        let listing: [String: Any] = ["AllDisksAndPartitions": [["DeviceIdentifier": "disk3", "APFSVolumes": [
            ["DeviceIdentifier": "disk3s1", "MountPoint": "/System/Volumes/Data"],
            ["DeviceIdentifier": "disk3s2", "MountPoint": "/System/Volumes/Preboot"],
            ["DeviceIdentifier": "disk3s3", "MountedSnapshots": [["SnapshotBSD": "disk3s3s1"]]],
            ["DeviceIdentifier": "disk3s3s1", "MountPoint": "/"]
        ]]]]
        let apfs: [String: Any] = ["Containers": [["ContainerReference": "disk3", "CapacityCeiling": 1000,
            "CapacityFree": 600, "PhysicalStores": [["DeviceIdentifier": "disk0s2"]], "Volumes": [
                ["DeviceIdentifier": "disk3s1", "APFSVolumeUUID": "data", "Name": "Data", "Roles": ["Data"], "CapacityInUse": 300],
                ["DeviceIdentifier": "disk3s2", "APFSVolumeUUID": "preboot", "Name": "Preboot", "Roles": ["Preboot"], "CapacityInUse": 20],
                ["DeviceIdentifier": "disk3s3", "APFSVolumeUUID": "system", "Name": "System", "Roles": ["System"], "CapacityInUse": 80]
            ]]]]
        let inventory = DiskInventoryReader.parse(listing: listing, apfs: apfs) { id in
            guard id != "disk3" else { return nil }
            let mount = ["disk3s1": "/System/Volumes/Data", "disk3s2": "/System/Volumes/Preboot", "disk3s3s1": "/"][id]
            return NativeDiskDescription(identity: id, name: id, filesystem: "apfs", mountPoint: mount,
                isInternal: true, isMountable: true, physicalDisks: ["disk3"], capacity: 1000, free: 600)
        }
        XCTAssertEqual(inventory.containers.count, 1)
        XCTAssertEqual(inventory.volumes.count, 3) // Snapshot replaces parent.
        XCTAssertFalse(inventory.volumes.contains { $0.id == "disk3s3" })
        XCTAssertEqual(Set(inventory.volumes.compactMap(\.free)), [600])
        XCTAssertEqual(inventory.volumes.first { $0.id == "disk3s1" }?.used, 300)
        XCTAssertTrue(inventory.volumes.allSatisfy(\.isProtected))
        XCTAssertTrue(inventory.volumes.allSatisfy { $0.physicalDisks == ["disk0"] })
        for volume in inventory.volumes { for action in [VolumeAction.mount, .unmount, .eject] { XCTAssertFalse(volume.allows(action)) } }
    }
    func testWholeDiskNames() {
        XCTAssertEqual(DiskInventoryReader.physicalDisk("disk12s3s1"), "disk12")
        XCTAssertEqual(DiskInventoryReader.physicalDisk("disk0"), "disk0")
    }
    func testActionEligibilityAndLockedVolumes() {
        let mounted = volume("disk4s1", mounted: true)
        XCTAssertTrue(mounted.allows(.unmount)); XCTAssertTrue(mounted.allows(.eject)); XCTAssertFalse(mounted.allows(.mount))
        XCTAssertTrue(volume("disk4s1", mounted: false).allows(.mount))
        XCTAssertFalse(volume("disk4s1", mounted: true, internalDisk: true).allows(.eject))
        for action in [VolumeAction.mount, .unmount, .eject] {
            XCTAssertFalse(volume("disk4s1", mounted: false, locked: true).allows(action))
            XCTAssertFalse(volume("disk4s1", mounted: true, protected: true).allows(action))
        }
        XCTAssertFalse(volume("disk4s1", mounted: true, physical: ["disk4", "disk5"]).allows(.eject))
    }
    func testActivitySamplingResetAndHotplug() {
        var sampler = ActivitySampler()
        XCTAssertTrue(sampler.sample(["disk0": .init(read: 100, written: 200)], at: 1).isEmpty)
        XCTAssertEqual(sampler.sample(["disk0": .init(read: 300, written: 300)], at: 3)["disk0"], .init(read: 100, written: 50))
        XCTAssertTrue(sampler.sample(["disk0": .init(read: 0, written: 0)], at: 4).isEmpty)
        XCTAssertTrue(sampler.sample(["disk2": .init(read: 50, written: 50)], at: 5).isEmpty)
        XCTAssertTrue(sampler.sample([:], at: 6).isEmpty)
    }
    @MainActor func testSharedActivityNotCountedTwiceAndSystemFilter() {
        let model = VolumeMatrixModel()
        model.inventory = VolumeInventory(volumes: [volume("disk4s1", mounted: true), volume("disk4s2", mounted: true)], containers: [])
        model.rates = ["disk4": .init(read: 50, written: 25)]
        XCTAssertEqual(model.totalRate, .init(read: 50, written: 25))
        XCTAssertEqual(model.mountedCount, 2)
        XCTAssertEqual(model.rate(for: model.volumes[0]), .init(read: 50, written: 25))
        model.rates = [:]
        XCTAssertNil(model.rate(for: model.volumes[0])); XCTAssertFalse(model.activityAvailable)
        model.inventory.volumes.append(volume("disk4s3", mounted: true, protected: true, helper: true))
        XCTAssertEqual(model.volumes.count, 2)
        model.showSystemVolumes = true
        XCTAssertEqual(model.volumes.count, 3)
    }
}

func volume(_ id: String, mounted: Bool, internalDisk: Bool = false, locked: Bool = false,
            protected: Bool = false, helper: Bool = false, physical: [String] = ["disk4"]) -> DiskVolume {
    DiskVolume(id: id, identity: id, name: "Test SSD", filesystem: "APFS", mountPoint: mounted ? "/Volumes/Test" : nil,
        isInternal: internalDisk, isMountable: true, isLocked: locked, isProtected: protected, isSystemHelper: helper,
        physicalDisks: physical, containerID: nil, used: 50, capacity: 100, free: 50)
}
