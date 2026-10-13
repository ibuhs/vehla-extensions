import Foundation
import DiskArbitration

struct NativeDiskDescription {
    let identity: String
    let name: String
    let filesystem: String
    let mountPoint: String?
    let isInternal: Bool
    let isMountable: Bool
    let physicalDisks: [String]
    let capacity: Int64?
    let free: Int64?
}

enum DiskInventoryReader {
    static func read() throws -> VolumeInventory {
        let listing = try plist(DiskCommand.run(["list", "-plist"]))
        let apfs = try plist(DiskCommand.run(["apfs", "list", "-plist"]))
        guard let session = DASessionCreate(kCFAllocatorDefault) else { throw DiskError.message("Disk service unavailable.") }
        return parse(listing: listing, apfs: apfs) { id in
            guard let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, id),
                  let info = DADiskCopyDescription(disk) as? [String: Any] else { return nil }
            let whole = DADiskCopyWholeDisk(disk)
            let wholeInfo = whole.flatMap { DADiskCopyDescription($0) as? [String: Any] } ?? [:]
            let protocolName = (info[kDADiskDescriptionDeviceProtocolKey as String] ?? wholeInfo[kDADiskDescriptionDeviceProtocolKey as String]) as? String ?? ""
            let modelName = (info[kDADiskDescriptionDeviceModelKey as String] ?? wholeInfo[kDADiskDescriptionDeviceModelKey as String]) as? String ?? ""
            let removable = (wholeInfo[kDADiskDescriptionMediaRemovableKey as String] ?? info[kDADiskDescriptionMediaRemovableKey as String]) as? Bool ?? false
            let ejectable = (wholeInfo[kDADiskDescriptionMediaEjectableKey as String] ?? info[kDADiskDescriptionMediaEjectableKey as String]) as? Bool ?? false
            let internalDevice = (info[kDADiskDescriptionDeviceInternalKey as String] ?? wholeInfo[kDADiskDescriptionDeviceInternalKey as String]) as? Bool ?? !(removable || ejectable || ["USB", "FireWire"].contains(protocolName))
            let wholeID = whole.flatMap { DADiskGetBSDName($0).map { String(cString: $0) } }
            let mount = (info[kDADiskDescriptionVolumePathKey as String] as? URL)?.path
            let values = mount.flatMap { try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]) }
            let uuid = (info[kDADiskDescriptionVolumeUUIDKey as String] as? UUID)?.uuidString
            return NativeDiskDescription(identity: uuid ?? id,
                name: info[kDADiskDescriptionVolumeNameKey as String] as? String ?? id,
                filesystem: info[kDADiskDescriptionVolumeKindKey as String] as? String ?? "Volume",
                mountPoint: mount,
                isInternal: modelName == "Disk Image" ? false : internalDevice,
                isMountable: info[kDADiskDescriptionVolumeMountableKey as String] as? Bool ?? false,
                physicalDisks: wholeID.map { [$0] } ?? [],
                capacity: values?.volumeTotalCapacity.map(Int64.init),
                free: values?.volumeAvailableCapacity.map(Int64.init))
        }
    }
    static func plist(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DiskError.message("macOS returned unreadable disk information.")
        }
        return result
    }
    static func physicalDisk(_ partition: String) -> String {
        // BSD names are diskN[sN...]; strip only after the numeric whole-disk ID.
        "disk" + partition.dropFirst(4).prefix(while: { $0.isNumber })
    }
    static func parse(listing: [String: Any], apfs: [String: Any], describe: (String) -> NativeDiskDescription?) -> VolumeInventory {
        var entries: [String: [String: Any]] = [:]
        func collect(_ nodes: [[String: Any]]) {
            for node in nodes {
                if let id = node["DeviceIdentifier"] as? String { entries[id] = node }
                collect(node["Partitions"] as? [[String: Any]] ?? [])
                collect(node["APFSVolumes"] as? [[String: Any]] ?? [])
            }
        }
        collect(listing["AllDisksAndPartitions"] as? [[String: Any]] ?? [])
        var containers: [APFSContainer] = []
        var metadata: [String: [String: Any]] = [:]
        var containerByVolume: [String: APFSContainer] = [:]
        for node in apfs["Containers"] as? [[String: Any]] ?? [] {
            guard let id = node["ContainerReference"] as? String else { continue }
            let stores = (node["PhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
            let physical = Array(Set(stores.map(physicalDisk))).sorted()
            let container = APFSContainer(id: id, capacity: (node["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0,
                free: (node["CapacityFree"] as? NSNumber)?.int64Value ?? 0, physicalDisks: physical)
            containers.append(container)
            for volume in node["Volumes"] as? [[String: Any]] ?? [] {
                guard let volumeID = volume["DeviceIdentifier"] as? String else { continue }
                metadata[volumeID] = volume
                containerByVolume[volumeID] = container
            }
        }
        // Map mounted sealed snapshots to their APFS parent; display the mount once.
        for (id, entry) in entries where entry["MountedSnapshots"] != nil {
            for snapshot in entry["MountedSnapshots"] as? [[String: Any]] ?? [] {
                guard let snapshotID = snapshot["SnapshotBSD"] as? String else { continue }
                metadata[snapshotID] = metadata[id]
                containerByVolume[snapshotID] = containerByVolume[id]
            }
        }
        var native: [String: NativeDiskDescription] = [:]
        for id in entries.keys { if let info = describe(id) { native[id] = info } }
        let bootContainers = Set(native.filter { $0.value.mountPoint == "/" || $0.value.mountPoint == "/System/Volumes/Data" }.compactMap { containerByVolume[$0.key]?.id })
        let bootPhysical = Set(native.filter { $0.value.mountPoint == "/" || $0.value.mountPoint == "/System/Volumes/Data" }.flatMap { containerByVolume[$0.key]?.physicalDisks ?? $0.value.physicalDisks })
        let helpers: Set<String> = ["Preboot", "Recovery", "VM", "Update", "Hardware", "xART", "ISC"]
        var volumes: [DiskVolume] = []
        for (id, info) in native {
            guard info.isMountable || info.mountPoint != nil || metadata[id] != nil else { continue }
            let entry = entries[id] ?? [:]
            // An APFS system volume with its mounted snapshot is one volume.
            if info.mountPoint == nil, !(entry["MountedSnapshots"] as? [[String: Any]] ?? []).isEmpty { continue }
            let meta = metadata[id] ?? [:]
            let roles = Set(meta["Roles"] as? [String] ?? [])
            let container = containerByVolume[id]
            let physical = container?.physicalDisks ?? info.physicalDisks
            let mount = info.mountPoint ?? entry["MountPoint"] as? String
            let helper = !roles.isDisjoint(with: helpers) || (entry["OSInternal"] as? Bool == true)
            let protected = helper || mount == "/" || mount == "/System/Volumes/Data" ||
                (container.map { bootContainers.contains($0.id) } ?? false) ||
                !Set(physical).isDisjoint(with: bootPhysical)
            let used = (meta["CapacityInUse"] as? NSNumber)?.int64Value ?? (entry["CapacityInUse"] as? NSNumber)?.int64Value ??
                info.capacity.flatMap { capacity in info.free.map { max(0, capacity - $0) } }
            volumes.append(DiskVolume(id: id, identity: meta["APFSVolumeUUID"] as? String ?? entry["VolumeUUID"] as? String ?? entry["DiskUUID"] as? String ?? info.identity,
                name: meta["Name"] as? String ?? entry["VolumeName"] as? String ?? info.name,
                filesystem: container == nil ? info.filesystem.uppercased() : "APFS",
                mountPoint: mount, isInternal: physical.isEmpty ? info.isInternal : physical.allSatisfy { native[$0]?.isInternal ?? true }, isMountable: info.isMountable,
                isLocked: meta["Locked"] as? Bool ?? false, isProtected: protected, isSystemHelper: helper,
                physicalDisks: physical, containerID: container?.id, used: used,
                capacity: container?.capacity ?? info.capacity, free: container?.free ?? info.free))
        }
        volumes.sort {
            if $0.mounted != $1.mounted { return $0.mounted }
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
        return VolumeInventory(volumes: volumes, containers: containers.sorted { $0.id < $1.id })
    }
}
