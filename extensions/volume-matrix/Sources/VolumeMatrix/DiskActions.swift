import Foundation
import DiskArbitration

private final class DiskRequest: @unchecked Sendable {
    let session: DASession
    let disk: DADisk
    let action: VolumeAction
    let continuation: CheckedContinuation<Void, any Error>
    let queue = DispatchQueue(label: "com.ibuhs.vehla.volume-action")
    init(session: DASession, disk: DADisk, action: VolumeAction, continuation: CheckedContinuation<Void, any Error>) {
        self.session = session; self.disk = disk; self.action = action; self.continuation = continuation
    }
    func begin() {
        DASessionSetDispatchQueue(session, queue)
        let context = Unmanaged.passRetained(self).toOpaque()
        switch action {
        case .mount: DADiskMount(disk, nil, DADiskMountOptions(kDADiskMountOptionDefault), diskFinished, context)
        case .unmount: DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), diskFinished, context)
        case .eject:
            DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), wholeUnmounted, context)
        }
    }
}
private func wholeUnmounted(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    if dissenter != nil { diskFinished(disk, dissenter, context); return }
    DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), diskFinished, context)
}
private func diskFinished(_ disk: DADisk, _ dissenter: DADissenter?, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let request = Unmanaged<DiskRequest>.fromOpaque(context).takeRetainedValue()
    DASessionSetDispatchQueue(request.session, nil)
    if let dissenter {
        let detail = DADissenterGetStatusString(dissenter).map { $0 as String } ?? "The disk may be in use or require authorization."
        request.continuation.resume(throwing: DiskError.message("macOS refused to \(request.action.rawValue) this volume. \(detail)"))
    } else { request.continuation.resume() }
}
enum DiskActions {
    static func perform(_ action: VolumeAction, volume: DiskVolume) async throws {
        // Fresh identity/boot checks prevent acting on a reused BSD name after hotplug.
        let current = try await Task.detached(priority: .userInitiated) { try DiskInventoryReader.read() }.value
        guard let fresh = current.volumes.first(where: { $0.id == volume.id && $0.identity == volume.identity }), fresh.allows(action) else {
            throw DiskError.message("This volume changed or cannot be \(action.rawValue)ed. Refresh the list.")
        }
        let target = action == .eject ? fresh.physicalDisks[0] : fresh.id
        if action == .eject {
            // APFS mounts live on synthesized disks. Unmount every sibling volume
            // explicitly before asking the physical device to eject.
            for sibling in current.volumes where sibling.mounted && sibling.physicalDisks.contains(target) {
                guard sibling.mountPoint != "/", sibling.mountPoint != "/System/Volumes/Data", !sibling.isInternal else {
                    throw DiskError.message("The startup or internal disk cannot be ejected.")
                }
                try await request(.unmount, target: sibling.id)
            }
        }
        try await request(action, target: target)
    }
    private static func request(_ action: VolumeAction, target: String) async throws {
        guard let session = DASessionCreate(kCFAllocatorDefault), let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, target) else {
            throw DiskError.message("The disk is no longer available.")
        }
        try await withCheckedThrowingContinuation { continuation in
            DiskRequest(session: session, disk: disk, action: action, continuation: continuation).begin()
        }
    }
}
