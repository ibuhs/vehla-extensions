import SwiftUI
import VehlaDockWidgetSDK

struct VolumeMatrixView: View {
    let surface: VehlaDockWidgetSurface
    @ObservedObject var model: VolumeMatrixModel
    @State private var ejectTarget: DiskVolume?
    private var tileColor: Color { Color(nsColor: model.theme?.tileTextColor ?? .labelColor) }
    var body: some View {
        Group {
            switch surface {
            case .compact:
                VStack(spacing: 4) {
                    Image(systemName: "externaldrive.fill").font(.title2)
                    Text("\(model.mountedCount) vols").font(.system(size: 10, weight: .semibold))
                }.foregroundStyle(tileColor).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .inline:
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                    Text("\(model.mountedCount) volumes")
                    Spacer()
                    if model.activityAvailable {
                        Text("↓ \(DiskFormat.rate(model.totalRate.read))").monospacedDigit()
                        Text("↑ \(DiskFormat.rate(model.totalRate.written))").monospacedDigit()
                    } else { Text("Activity —") }
                }.font(.caption).foregroundStyle(tileColor).padding(10)
            case .popup: popup
            @unknown default: EmptyView()
            }
        }.tint(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .environment(\.colorScheme, model.theme?.isDark == true ? .dark : .light)
        .alert("Eject \(ejectTarget?.name ?? "disk")?", isPresented: Binding(get: { ejectTarget != nil }, set: { if !$0 { ejectTarget = nil } })) {
            Button("Cancel", role: .cancel) { ejectTarget = nil }
            Button("Eject") { if let target = ejectTarget { model.perform(.eject, on: target) }; ejectTarget = nil }
        } message: { Text("All volumes on this physical disk will be unmounted. Ejected disks may need to be reconnected before they can be mounted again.") }
    }
    private var popup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Volume Matrix", systemImage: "externaldrive.fill").font(.title2.bold())
                    Spacer()
                    if model.loading { ProgressView().controlSize(.small) }
                    Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh).labelStyle(.iconOnly).disabled(model.loading)
                        .accessibilityIdentifier("volumes.refresh")
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
                if model.inventory.volumes.isEmpty {
                    Text(model.loading ? "Reading volumes…" : "No disk volumes found.").foregroundStyle(.secondary)
                }
                if !model.displayedContainers.isEmpty {
                    Text("APFS storage").font(.headline)
                    ForEach(model.displayedContainers) { container in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(containerName(container)).font(.subheadline.bold())
                                    Spacer()
                                    Text("\(DiskFormat.bytes(container.free)) free").monospacedDigit()
                                }
                                ProgressView(value: Double(container.used), total: Double(max(1, container.capacity))).tint(.green)
                                Text("\(DiskFormat.bytes(container.used)) used of \(DiskFormat.bytes(container.capacity)) · Shared by APFS volumes")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(6)
                        }
                    }
                }
                Text("Mounted volumes").font(.headline)
                ForEach(model.volumes.filter(\.mounted)) { volume in volumeCard(volume) }
                if !model.volumes.filter({ !$0.mounted }).isEmpty {
                    Text("Available to mount").font(.headline)
                    ForEach(model.volumes.filter { !$0.mounted }) { volume in volumeCard(volume) }
                }
                Divider()
                Toggle("Show system volumes", isOn: $model.showSystemVolumes)
                    .accessibilityIdentifier("volumes.system-toggle")
                HStack {
                    Text("Activity is measured for each physical disk and shared by its volumes.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Disk Utility", action: model.openDiskUtility)
                }
            }.padding(20)
        }.foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
    }
    private func containerName(_ container: APFSContainer) -> String {
        let names = model.volumes.filter { $0.containerID == container.id && !$0.isSystemHelper }.map(\.name)
        return (names.first ?? "APFS container") + " · " + container.id
    }
    private func volumeCard(_ volume: DiskVolume) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: volume.icon).font(.title2).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(volume.name).font(.headline)
                        Text("\(volume.filesystem) · \(volume.isInternal ? "Internal" : "External") · \(volume.isLocked ? "Locked" : volume.mounted ? "Mounted" : "Unmounted")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.busyVolume == volume.id { ProgressView().controlSize(.small) }
                }
                if let used = volume.used {
                    if volume.containerID == nil, let capacity = volume.capacity {
                        ProgressView(value: Double(used), total: Double(max(1, capacity))).tint(.green)
                    }
                    Text(volume.containerID != nil ? "Volume uses \(DiskFormat.bytes(used)) · \(DiskFormat.bytes(volume.free)) shared free" : "\(DiskFormat.bytes(used)) used · \(DiskFormat.bytes(volume.free)) free")
                        .font(.caption).monospacedDigit()
                }
                if let rate = model.rate(for: volume) {
                    HStack {
                        Label(DiskFormat.rate(rate.read), systemImage: "arrow.down").accessibilityLabel("Read \(DiskFormat.rate(rate.read))")
                        Label(DiskFormat.rate(rate.written), systemImage: "arrow.up").accessibilityLabel("Write \(DiskFormat.rate(rate.written))")
                        Spacer()
                        Text("Device activity").foregroundStyle(.secondary)
                    }.font(.caption).monospacedDigit()
                } else { Text("Device activity unavailable").font(.caption).foregroundStyle(.secondary) }
                HStack {
                    if volume.mounted { Button("Open") { model.open(volume) } }
                    if volume.allows(.mount) { Button("Mount") { model.perform(.mount, on: volume) } }
                    if volume.allows(.unmount) { Button("Unmount") { model.perform(.unmount, on: volume) } }
                    if volume.allows(.eject) { Button("Eject", systemImage: "eject") { ejectTarget = volume } }
                    Spacer()
                    if volume.isProtected { Label("System disk", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                    if volume.isLocked { Text("Unlock in Disk Utility").font(.caption).foregroundStyle(.secondary) }
                }.disabled(model.busyVolume != nil)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }.accessibilityIdentifier("volumes.volume.\(volume.id)")
    }
}
