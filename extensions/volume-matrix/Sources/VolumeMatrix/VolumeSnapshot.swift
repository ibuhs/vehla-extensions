import Foundation

enum VolumeAction: String, Sendable { case mount, unmount, eject }

struct DiskVolume: Identifiable, Equatable, Sendable {
    let id: String
    let identity: String
    let name: String
    let filesystem: String
    let mountPoint: String?
    let isInternal: Bool
    let isMountable: Bool
    let isLocked: Bool
    let isProtected: Bool
    let isSystemHelper: Bool
    let physicalDisks: [String]
    let containerID: String?
    let used: Int64?
    let capacity: Int64?
    let free: Int64?
    var mounted: Bool { mountPoint != nil }
    var icon: String { isInternal ? "internaldrive.fill" : "externaldrive.fill" }
    func allows(_ action: VolumeAction) -> Bool {
        guard !isProtected, !isLocked else { return false }
        switch action {
        case .mount: return !mounted && isMountable
        case .unmount: return mounted
        case .eject: return !isInternal && physicalDisks.count == 1
        }
    }
}

struct APFSContainer: Identifiable, Equatable, Sendable {
    let id: String
    let capacity: Int64
    let free: Int64
    let physicalDisks: [String]
    var used: Int64 { max(0, capacity - free) }
}
struct VolumeInventory: Equatable, Sendable {
    var volumes: [DiskVolume] = []
    var containers: [APFSContainer] = []
}
struct DiskCounters: Equatable, Sendable {
    let read: UInt64
    let written: UInt64
}
struct DiskRate: Equatable, Sendable {
    let read: Double
    let written: Double
}
struct ActivitySampler: Sendable {
    private var previous: [String: DiskCounters] = [:]
    private var time: TimeInterval?
    mutating func sample(_ counters: [String: DiskCounters], at now: TimeInterval) -> [String: DiskRate] {
        defer { previous = counters; time = now }
        guard let time, now > time else { return [:] }
        let elapsed = now - time
        return counters.reduce(into: [:]) { result, entry in
            guard let old = previous[entry.key], entry.value.read >= old.read,
                  entry.value.written >= old.written else { return }
            result[entry.key] = DiskRate(read: Double(entry.value.read - old.read) / elapsed,
                written: Double(entry.value.written - old.written) / elapsed)
        }
    }
}
enum DiskFormat {
    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .decimal)
    }
    static func rate(_ value: Double) -> String { bytes(Int64(max(0, min(value, Double(Int64.max / 2))))) + "/s" }
}
