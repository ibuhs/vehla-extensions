import Foundation
@preconcurrency import CoreBluetooth

@MainActor protocol BluetoothBatteryControlling: AnyObject {
    var enabled: Bool { get }
    var snapshots: [UUID: PeripheralSnapshot] { get }
    var onChange: (() -> Void)? { get set }
    var onError: ((String?) -> Void)? { get set }
    func start()
    func stop()
    func refresh(force: Bool)
}

enum BatteryRefreshAction: Equatable { case connect, wait, discoverServices, discoverCharacteristics, read, none }
/// The same retry decisions drive native discovery and regression tests.
enum BatteryRefreshPolicy {
    static func action(state: CBPeripheralState, hasService: Bool, hasReadableLevel: Bool,
                       lastRead: Date?, force: Bool, now: Date) -> BatteryRefreshAction {
        switch state {
        case .disconnected: return .connect
        case .connecting, .disconnecting: return .wait
        case .connected:
            if !hasService { return .discoverServices }
            if !hasReadableLevel { return .discoverCharacteristics }
            return force || now.timeIntervalSince(lastRead ?? .distantPast) >= 60 ? .read : .none
        @unknown default: return .wait
        }
    }
}

enum BluetoothStateWarning {
    @MainActor static func schedule(delay: Duration = .seconds(2), isStillOff: @escaping @MainActor () -> Bool,
                                    report: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, isStillOff() else { return }
            report()
        }
    }
}

@MainActor final class BluetoothBattery: NSObject, BluetoothBatteryControlling, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var lastRead: [UUID: Date] = [:]
    private var lastProbe: [UUID: Date] = [:]
    private var connectingSince: [UUID: Date] = [:]
    private var lastDiscovery = Date.distantPast
    private var scanTask: Task<Void, Never>?
    private var stateWarningTask: Task<Void, Never>?
    private(set) var snapshots: [UUID: PeripheralSnapshot] = [:]
    var onChange: (() -> Void)?
    var onError: ((String?) -> Void)?
    private let batteryService = CBUUID(string: "180F")
    private let hidService = CBUUID(string: "1812")
    private let batteryLevel = CBUUID(string: "2A19")
    private(set) var enabled = false
    func start() {
        guard !enabled else { refresh(force: true); return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil else {
            onError?("Vehla must declare NSBluetoothAlwaysUsageDescription in its app Info.plist before Bluetooth battery discovery can run.")
            return
        }
        enabled = true
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func stop() {
        enabled = false; scanTask?.cancel(); scanTask = nil
        stateWarningTask?.cancel(); stateWarningTask = nil
        onError?(nil)
        central?.stopScan()
        for peripheral in peripherals.values { peripheral.delegate = nil; central?.cancelPeripheralConnection(peripheral) }
        peripherals.removeAll(); snapshots.removeAll(); lastRead.removeAll(); lastProbe.removeAll(); connectingSince.removeAll()
        lastDiscovery = .distantPast
        central?.delegate = nil; central = nil; onChange?()
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard enabled, self.central === central else { return }
        stateWarningTask?.cancel(); stateWarningTask = nil
        onError?(nil)
        switch central.state {
        case .poweredOn: refresh(force: true)
        case .unauthorized: onError?("Bluetooth access is denied. Allow Vehla in System Settings → Privacy & Security → Bluetooth."); clearDisconnected()
        case .poweredOff:
            clearDisconnected()
            // Core Bluetooth can briefly report off during wake/startup. Only
            // show a warning if the same active manager still reports off later.
            stateWarningTask = BluetoothStateWarning.schedule(isStillOff: { [weak self, weak central] in
                guard let self, let central else { return false }
                return self.enabled && self.central === central && central.state == .poweredOff
            }, report: { [weak self] in
                self?.onError?("Bluetooth LE discovery is unavailable while macOS reports Bluetooth off.")
            })
        case .unsupported: onError?("Bluetooth LE is unavailable on this Mac."); clearDisconnected()
        case .resetting: clearDisconnected()
        default: break
        }
    }
    private func clearDisconnected() {
        scanTask?.cancel(); scanTask = nil
        for peripheral in peripherals.values { peripheral.delegate = nil }
        snapshots.removeAll(); peripherals.removeAll(); lastRead.removeAll(); lastProbe.removeAll(); connectingSince.removeAll()
        lastDiscovery = .distantPast; onChange?()
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard enabled, self.central === central else { return }
        adopt(peripheral)
    }
    private func adopt(_ peripheral: CBPeripheral, probeNow: Bool = true) {
        guard enabled else { return }
        let fresh = peripherals[peripheral.identifier] == nil
        peripherals[peripheral.identifier] = peripheral; peripheral.delegate = self
        if fresh && peripheral.state == .connected {
            // A retrieved, already-connected device may not emit a new didConnect.
            central?.connect(peripheral, options: nil)
            if probeNow { probe(peripheral, force: true) }
        } else if probeNow { probe(peripheral, force: fresh) }
    }
    private func accepts(_ peripheral: CBPeripheral) -> Bool {
        enabled && peripherals[peripheral.identifier] === peripheral
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.central === central, accepts(peripheral) else { return }
        connectingSince.removeValue(forKey: peripheral.identifier)
        probe(peripheral, force: true)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard self.central === central, accepts(peripheral) else { return }
        remove(peripheral)
        onError?("Could not connect to \(peripheral.name ?? "Bluetooth peripheral"): \(error?.localizedDescription ?? "connection failed")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard self.central === central, accepts(peripheral) else { return }
        remove(peripheral)
    }
    private func remove(_ peripheral: CBPeripheral) {
        peripherals.removeValue(forKey: peripheral.identifier); snapshots.removeValue(forKey: peripheral.identifier)
        lastRead.removeValue(forKey: peripheral.identifier); lastProbe.removeValue(forKey: peripheral.identifier)
        connectingSince.removeValue(forKey: peripheral.identifier); peripheral.delegate = nil; onChange?()
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard accepts(peripheral) else { return }
        guard error == nil else { onError?(error!.localizedDescription); return }
        for service in peripheral.services ?? [] where service.uuid == batteryService { peripheral.discoverCharacteristics([batteryLevel], for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard accepts(peripheral), service.uuid == batteryService else { return }
        guard error == nil else { onError?(error!.localizedDescription); return }
        for characteristic in service.characteristics ?? [] where characteristic.uuid == batteryLevel {
            if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
            if characteristic.properties.contains(.notify), !characteristic.isNotifying { peripheral.setNotifyValue(true, for: characteristic) }
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard accepts(peripheral), invalidatedServices.contains(where: { $0.uuid == batteryService }) else { return }
        lastRead.removeValue(forKey: peripheral.identifier)
        snapshots.removeValue(forKey: peripheral.identifier); onChange?()
        peripheral.discoverServices([batteryService])
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard accepts(peripheral), characteristic.uuid == batteryLevel else { return }
        guard error == nil, let data = characteristic.value, data.count == 1,
              let battery = PeripheralSnapshot.batteryPercent(Int(data[0])) else {
            snapshots.removeValue(forKey: peripheral.identifier); lastRead.removeValue(forKey: peripheral.identifier); onChange?(); return
        }
        snapshots[peripheral.identifier] = PeripheralSnapshot(id: "ble.\(peripheral.identifier.uuidString)",
            name: peripheral.name ?? "Bluetooth LE peripheral", transport: "Bluetooth LE", kind: "Peripheral", battery: battery)
        lastRead[peripheral.identifier] = Date(); onChange?()
    }
    func refresh(force: Bool = false) {
        guard enabled, let central, central.state == .poweredOn else { return }
        onError?(nil)
        if force || Date().timeIntervalSince(lastDiscovery) >= 30 {
            lastDiscovery = Date()
            // HID devices often advertise 1812 rather than their battery service.
            for peripheral in central.retrieveConnectedPeripherals(withServices: [batteryService, hidService]) { adopt(peripheral, probeNow: false) }
            central.stopScan()
            central.scanForPeripherals(withServices: [batteryService], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            scanTask?.cancel()
            scanTask = Task { [weak self, weak central] in
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, self?.enabled == true else { return }
                central?.stopScan()
            }
        }
        for peripheral in Array(peripherals.values) { probe(peripheral, force: force) }
    }
    private func probe(_ peripheral: CBPeripheral, force: Bool) {
        let now = Date(), id = peripheral.identifier
        if peripheral.state == .connecting, now.timeIntervalSince(connectingSince[id] ?? now) >= 15 {
            central?.cancelPeripheralConnection(peripheral)
            remove(peripheral) // The next bounded discovery retrieves/reconnects it.
            return
        }
        guard force || now.timeIntervalSince(lastProbe[id] ?? .distantPast) >= 15 else { return }
        let service = peripheral.services?.first { $0.uuid == batteryService }
        let level = service?.characteristics?.first { $0.uuid == batteryLevel && $0.properties.contains(.read) }
        switch BatteryRefreshPolicy.action(state: peripheral.state, hasService: service != nil,
            hasReadableLevel: level != nil, lastRead: lastRead[id], force: force, now: now) {
        case .connect:
            connectingSince[id] = now; central?.connect(peripheral, options: nil)
        case .discoverServices: peripheral.discoverServices([batteryService])
        case .discoverCharacteristics:
            if let service { peripheral.discoverCharacteristics([batteryLevel], for: service) }
        case .read: if let level { peripheral.readValue(for: level) }
        case .wait, .none: return
        }
        lastProbe[id] = now
    }
}
