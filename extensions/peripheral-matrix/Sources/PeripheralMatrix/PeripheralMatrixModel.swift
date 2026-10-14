import AppKit
import IOKit.hid
import Combine
import VehlaDockWidgetSDK

@MainActor final class PeripheralMatrixModel: ObservableObject {
    private var programmingWindow: QMKProgrammingWindowController?
    private var programmingVisible = false
    private var programmingPoll: Task<Void, Never>?
    private var automaticLoadAttemptID: String?
    let editor = QMKEditorModel()
    @Published var editorConnectionID: String?
    @Published var editingProfiles = false
    @Published var devices: [PeripheralSnapshot] = []
    @Published var layers: [LayerConnection] = []
    @Published var bluetoothEnabled = false
    @Published var bridgeEnabled = false
    @Published var theme: VehlaDockWidgetTheme?
    @Published var error: String?
    @Published var bluetoothError: String?
    @Published var bridgeTestResult: String?
    @Published var profileNames: [String: [String: String]] = [:]
    private var editorChanges: AnyCancellable?
    private var context: VehlaDockWidgetContext?
    private let bluetooth: any BluetoothBatteryControlling
    private let bridge = LayerBridge()
    private var poll: Task<Void, Never>?
    private let readRegistry: @Sendable () async -> [PeripheralSnapshot]
    private var registryTask: Task<Void, Never>?
    private var lastRegistryRead = Date.distantPast
    private var registry: [PeripheralSnapshot] = []
    private var visible = false
    private var resumeBridge = false
    init(readRegistry: (@Sendable () async -> [PeripheralSnapshot])? = nil, bluetooth: (any BluetoothBatteryControlling)? = nil) {
        self.bluetooth = bluetooth ?? BluetoothBattery()
        let reader = RegistryReader()
        self.readRegistry = readRegistry ?? { await reader.read() }
        editorChanges = editor.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }
    func waitForRegistryRefresh() async { await registryTask?.value }
    var lowestPeripheral: PeripheralSnapshot? {
        devices.filter { PeripheralSnapshot.batteryPercent($0.battery) != nil }.min {
            if $0.battery != $1.battery { return ($0.battery ?? 101) < ($1.battery ?? 101) }
            return $0.id < $1.id
        }
    }
    var lowestBattery: Int? { lowestPeripheral?.battery }
    var dockIcon: String { lowestPeripheral?.icon ?? "keyboard" }
    func configure(_ context: VehlaDockWidgetContext) {
        theme = context.theme
        guard self.context == nil else { return }
        self.context = context
        if let data = try? Data(contentsOf: context.dataDirectory.appendingPathComponent("profile-names.json")),
           let names = try? JSONDecoder().decode([String: [String: String]].self, from: data) { profileNames = names }
        bluetooth.onChange = { [weak self] in self?.publish() }
        bluetooth.onError = { [weak self] in self?.bluetoothError = $0 }
        bridge.onChange = { [weak self] in self?.publish(layerChanged: true) }
        bridge.onError = { [weak self] in self?.error = $0 }
        refresh()
    }
    func start() {
        guard !visible else { return }
        visible = true
        bluetooth.start(); bluetoothEnabled = bluetooth.enabled
        if resumeBridge { bridge.start(); bridgeEnabled = bridge.enabled }
        poll?.cancel()
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.refresh(forceRegistry: false)
            }
        }
        refresh()
    }
    func hide() {
        guard visible else { return }
        visible = false; poll?.cancel(); poll = nil
        registryTask?.cancel(); registryTask = nil
        resumeBridge = bridgeEnabled
        bluetooth.stop(); bluetoothEnabled = false
        if programmingVisible { return }
        stopBridgeWhenIdle()
    }
    private func stopBridgeWhenIdle() {
        if editor.busy {
            Task { [weak self] in
                guard let self else { return }
                await self.editor.waitForOperation()
                guard !self.visible && !self.programmingVisible else { return }
                self.editor.invalidate(); self.bridge.stop(); self.bridgeEnabled = false
            }
        } else { editor.invalidate(); bridge.stop(); bridgeEnabled = false }
    }
    func close() {
        programmingWindow?.close()
        hide()
        if bluetooth.enabled { bluetooth.stop(); bluetoothEnabled = false }
        if bridge.enabled && !editor.busy { bridge.stop(); bridgeEnabled = false }
        resumeBridge = false
    }
    func setBridge(_ enabled: Bool) {
        guard !editor.busy else { return }
        if !enabled { editor.invalidate() }
        error = nil
        enabled ? bridge.start() : bridge.stop()
        bridgeEnabled = bridge.enabled; resumeBridge = bridgeEnabled
        publish()
    }
    func testBridge() {
        guard bridgeEnabled else { return }
        error = nil
        bridgeTestResult = "Testing keyboard reply…"
        // Retry the bounded handshake without interrupting input registrations.
        bridge.testConnections()
        publish(layerChanged: true)
    }
    func refresh() { refresh(forceRegistry: true) }
    private func refresh(forceRegistry: Bool) {
        if registryTask == nil && (forceRegistry || Date().timeIntervalSince(lastRegistryRead) >= 30) {
            registryTask = Task { [weak self, readRegistry] in
                let snapshot = await readRegistry()
                guard !Task.isCancelled, let self else { return }
                self.registryTask = nil
                self.lastRegistryRead = Date()
                self.registry = snapshot
                self.publish()
            }
        }
        if bluetooth.enabled { bluetooth.refresh(force: forceRegistry) }
        if visible || programmingVisible { bridge.refresh() }
    }
    private func publish(layerChanged: Bool = false) {
        let updatedDevices = PeripheralInventory.merge(registry, batteries: Array(bluetooth.snapshots.values))
        if devices != updatedDevices { devices = updatedDevices }
        let updatedLayers = bridge.connections.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let editorConnectionID, !updatedLayers.contains(where: { $0.id == editorConnectionID }) {
            editor.invalidate(); automaticLoadAttemptID = nil
        }
        if layers.map(\.id) != updatedLayers.map(\.id) { layers = updatedLayers }
        else if layerChanged { objectWillChange.send() }
        loadConnectedKeyboardIfNeeded()
        if bridgeTestResult != nil {
            let access = CGPreflightListenEventAccess() ? "granted" : "not granted"
            let details = updatedLayers.map { connection in
                let state = connection.state.map { "Confirmed \($0.count) layers; active \(name(connection, layer: $0.active))." } ?? "Waiting for bridge reply."
                return "\(connection.name): \(state) Requests sent: \(connection.requestsSent); reports received: \(connection.reportsReceived); last report: \(connection.lastReportLength) bytes; HID result: \(connection.lastSendResult.map(String.init) ?? "none")."
            }.joined(separator: "\n")
            let result = "Input Monitoring: \(access).\n" + (details.isEmpty ? "No Raw HID keyboard interface found." : details)
            if bridgeTestResult != result { bridgeTestResult = result }
        }
    }
    func openProgramming() {
        if let programmingWindow { programmingWindow.present(); return }
        programmingVisible = true
        if !bridgeEnabled { setBridge(true) }
        loadConnectedKeyboardIfNeeded()
        programmingPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.bridge.refresh()
            }
        }
        let controller = QMKProgrammingWindowController(model: self)
        controller.onClose = { [weak self] in
            guard let self else { return }
            self.programmingVisible = false
            self.programmingPoll?.cancel(); self.programmingPoll = nil
            self.programmingWindow = nil
            if !self.visible { self.stopBridgeWhenIdle() }
        }
        programmingWindow = controller
        controller.present()
    }
    private func loadConnectedKeyboardIfNeeded() {
        guard programmingVisible, !editor.busy, editor.changes.isEmpty,
              let connection = layers.first(where: { $0.keymapProfile != nil }),
              automaticLoadAttemptID != connection.id,
              editor.baseline == nil || editor.needsReload else { return }
        automaticLoadAttemptID = connection.id
        loadKeymap(connection)
    }
    func loadKeymap(_ connection: LayerConnection) {
        guard let context, !editor.busy, editor.changes.isEmpty else { return }
        automaticLoadAttemptID = connection.id
        editorConnectionID = connection.id
        editor.load(endpoint: connection, directory: context.dataDirectory)
    }
    var editorLayerNames: [String] {
        guard let connection = layers.first(where: { $0.id == editorConnectionID }) else { return ["Mac", "Mac Fn", "Windows", "Windows Fn"] }
        return (0..<4).map { name(connection, layer: UInt8($0)) }
    }
    func name(_ connection: LayerConnection, layer: UInt8) -> String {
        let vendor = IOHIDDeviceGetProperty(connection.device, kIOHIDVendorIDKey as CFString) as? NSNumber
        let product = IOHIDDeviceGetProperty(connection.device, kIOHIDProductIDKey as CFString) as? NSNumber
        return profileNames[profileKey(connection)]?[String(layer)] ?? LayerProtocol.defaultName(
            layer: layer, vendor: vendor?.uint32Value ?? 0, product: product?.uint32Value ?? 0)
    }
    private func profileKey(_ connection: LayerConnection) -> String {
        // Registry IDs change after reconnect; use stable USB identity for labels.
        let device = connection.device
        let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        return "\(vendor?.uint32Value ?? 0):\(product?.uint32Value ?? 0):\(serial):\(connection.name)"
    }
    func rename(_ connection: LayerConnection, layer: UInt8, name: String) {
        let key = profileKey(connection)
        profileNames[key, default: [:]][String(layer)] = String(name.prefix(60))
        guard let context else { return }
        do {
            try FileManager.default.createDirectory(at: context.dataDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(profileNames).write(to: context.dataDirectory.appendingPathComponent("profile-names.json"), options: .atomic)
        } catch { self.error = "Could not save profile labels: \(error.localizedDescription)" }
    }
}
