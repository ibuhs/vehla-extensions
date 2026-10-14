import AppKit
import Combine
import VehlaDockWidgetSDK

@MainActor final class VolumeMatrixModel: ObservableObject {
    @Published var inventory = VolumeInventory()
    @Published var rates: [String: DiskRate] = [:]
    @Published var theme: VehlaDockWidgetTheme?
    @Published var showSystemVolumes = false
    @Published var loading = false
    @Published var busyVolume: String?
    @Published var error: String?
    private var visible = false
    private var refreshTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var operation: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private var sampler = ActivitySampler()
    private var notifications: [NSObjectProtocol] = []
    var volumes: [DiskVolume] { inventory.volumes.filter { showSystemVolumes || !$0.isSystemHelper } }
    var mountedCount: Int { inventory.volumes.filter { $0.mounted && !$0.isSystemHelper }.count }
    var displayedContainers: [APFSContainer] {
        let ids = Set(volumes.compactMap(\.containerID))
        return inventory.containers.filter { ids.contains($0.id) }
    }
    var activityAvailable: Bool { !Set(inventory.volumes.flatMap(\.physicalDisks)).isDisjoint(with: rates.keys) }
    var totalRate: DiskRate {
        let physical = Set(inventory.volumes.flatMap(\.physicalDisks))
        return physical.reduce(DiskRate(read: 0, written: 0)) { sum, id in
            DiskRate(read: sum.read + (rates[id]?.read ?? 0), written: sum.written + (rates[id]?.written ?? 0))
        }
    }
    func rate(for volume: DiskVolume) -> DiskRate? {
        guard !volume.physicalDisks.isEmpty, volume.physicalDisks.allSatisfy({ rates[$0] != nil }) else { return nil }
        return volume.physicalDisks.reduce(DiskRate(read: 0, written: 0)) { sum, id in
            DiskRate(read: sum.read + (rates[id]?.read ?? 0), written: sum.written + (rates[id]?.written ?? 0))
        }
    }
    func start() {
        guard !visible else { return }
        visible = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
        }
        refresh()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                let counters = await Task.detached(priority: .utility) { DiskActivityReader.read() }.value
                guard !Task.isCancelled, let self, self.visible else { return }
                let rates = self.sampler.sample(counters, at: ProcessInfo.processInfo.systemUptime)
                if self.rates != rates { self.rates = rates }
                if Date().timeIntervalSince(self.lastRefresh) >= 30 { self.refresh() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func hide() {
        visible = false; timer?.cancel(); timer = nil
        refreshTask?.cancel(); refreshTask = nil; loading = false
        sampler = ActivitySampler(); rates = [:]
        for token in notifications { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        notifications = []
    }
    func refresh() {
        guard refreshTask == nil else { return }
        loading = true
        refreshTask = Task { [weak self] in
            do {
                let snapshot = try await Task.detached(priority: .utility) { try DiskInventoryReader.read() }.value
                guard !Task.isCancelled, let self else { return }
                if self.inventory != snapshot { self.inventory = snapshot }
            } catch {
                guard !Task.isCancelled else { return }
                self?.error = error.localizedDescription
            }
            self?.lastRefresh = Date(); self?.loading = false; self?.refreshTask = nil
        }
    }
    func perform(_ action: VolumeAction, on volume: DiskVolume) {
        guard busyVolume == nil, volume.allows(action) else { return }
        busyVolume = volume.id; error = nil
        operation = Task { [weak self] in
            do { try await DiskActions.perform(action, volume: volume) }
            catch { self?.error = error.localizedDescription }
            self?.busyVolume = nil; self?.operation = nil; self?.refresh()
        }
    }
    func open(_ volume: DiskVolume) {
        guard let path = volume.mountPoint else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    func openDiskUtility() { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app")) }
}
