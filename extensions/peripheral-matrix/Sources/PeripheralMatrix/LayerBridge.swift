import Foundation
import IOKit.hid

@MainActor final class LayerConnection: Identifiable, VIAEndpoint {
    let id: String
    let name: String
    let device: IOHIDDevice
    var state: LayerProtocol.State?
    var lastResponse: Date?
    var pendingLayer: UInt8?
    var pendingSince: Date?
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    // Allocation stays alive until dispatch cancellation drains device callbacks.
    nonisolated(unsafe) private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: LayerProtocol.size)
    private var opened = false
    private(set) var editingKeymap = false
    private var pendingVIA: PendingVIAReply?
    var keymapProfile: QMKKeyboardProfile? {
        let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.uint32Value
        let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.uint32Value
        return QMKKeyboardCatalog.profile(vendor: vendor ?? 0, product: product ?? 0)
    }
    var keymapIdentity: String {
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        return "\(keymapProfile?.id ?? "unsupported"):\(serial):\(id)"
    }
    private var sending = false
    private var handshakeAttempts = 0
    private var testing = false
    private var retryPending = false
    private(set) var requestsSent = 0
    private(set) var reportsReceived = 0
    private(set) var lastReportLength = 0
    private(set) var lastSendResult: IOReturn?
    init(device: IOHIDDevice, id: String) {
        self.device = device; self.id = id
        name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Raw HID keyboard"
    }
    func open() -> Bool {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return false }
        opened = true
        // Deliver device reports through the main dispatch queue, independently
        // of AppKit's popup/menu run-loop modes.
        IOHIDDeviceSetDispatchQueue(device, DispatchQueue.main)
        let callbackContext = Unmanaged.passRetained(self).toOpaque()
        let callbackAddress = UInt(bitPattern: callbackContext)
        IOHIDDeviceSetCancelHandler(device) {
            Unmanaged<LayerConnection>.fromOpaque(UnsafeMutableRawPointer(bitPattern: callbackAddress)!).release()
        }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, LayerProtocol.size, { context, result, _, _, _, report, length in
            guard let context, result == kIOReturnSuccess else { return }
            // IOHID callbacks run on the main dispatch queue selected above.
            MainActor.assumeIsolated {
                let connection = Unmanaged<LayerConnection>.fromOpaque(context).takeUnretainedValue()
                guard connection.opened else { return }
                connection.reportsReceived += 1; connection.lastReportLength = length
                guard length == LayerProtocol.size else { return }
                let bytes = Array(UnsafeBufferPointer(start: report, count: length))
                if let pending = connection.pendingVIA, VIAProtocol.matches(bytes, request: pending.packet) {
                    connection.finishVIA(.success(bytes))
                } else if let state = LayerProtocol.decode(bytes) {
                    let changed = connection.state != state || connection.pendingLayer != nil
                    connection.state = state; connection.lastResponse = Date(); connection.handshakeAttempts = 0
                    if connection.pendingLayer == state.active { connection.pendingLayer = nil; connection.pendingSince = nil }
                    if changed || connection.testing { connection.onChange?() }
                } else {
                    if connection.testing && !connection.editingKeymap { connection.onChange?() }
                }
            }
        }, callbackContext)
        IOHIDDeviceActivate(device)
        query(); return true
    }
    private func send(_ packet: [UInt8]) -> Bool {
        guard opened, !sending else { return false }
        let report = PendingHIDReport(packet: packet, connection: self)
        let context = Unmanaged.passRetained(report).toOpaque()
        sending = true
        let result = IOHIDDeviceSetReportWithCallback(device, kIOHIDReportTypeOutput, 0,
            report.bytes, packet.count, 500, { context, result, _, _, _, _, _ in
                guard let context else { return }
                let report = Unmanaged<PendingHIDReport>.fromOpaque(context).takeRetainedValue()
                MainActor.assumeIsolated {
                    guard let connection = report.connection, connection.opened else { return }
                    connection.sending = false
                    connection.lastSendResult = result
                    if result != kIOReturnSuccess {
                        connection.finishVIA(.failure(VIAError.message("HID write failed (\(result)). Reload the keymap before retrying.")))
                        connection.onError?("\(connection.name): HID report failed (\(result)). Check device connection and Input Monitoring permission.")
                    }
                    if connection.testing && !connection.editingKeymap { connection.onChange?() }
                    if connection.retryPending && !connection.editingKeymap {
                        connection.retryPending = false
                        connection.query()
                    }
                }
            }, context)
        if result != kIOReturnSuccess {
            Unmanaged<PendingHIDReport>.fromOpaque(context).release()
            sending = false
            onError?("\(name): HID report failed (\(result)). Check device connection and Input Monitoring permission.")
        }
        lastSendResult = result
        if result == kIOReturnSuccess { requestsSent += 1 }
        return result == kIOReturnSuccess
    }
    func query() {
        guard !editingKeymap else { return }
        if let since = pendingSince, Date().timeIntervalSince(since) > 3 {
            pendingLayer = nil; pendingSince = nil; onError?("\(name) did not confirm the requested layer. The displayed layer remains device-reported.")
        }
        if let lastResponse, Date().timeIntervalSince(lastResponse) > 10 { state = nil; onChange?() }
        // Unknown firmware gets a bounded handshake, not endless background reports.
        guard state != nil || handshakeAttempts < 3 else { return }
        if send(LayerProtocol.query()), state == nil { handshakeAttempts += 1 }
    }
    func select(_ layer: UInt8) {
        guard !editingKeymap, let state, let packet = LayerProtocol.set(layer: layer, count: state.count), pendingLayer == nil else { return }
        if send(packet) { pendingLayer = layer; pendingSince = Date(); onChange?() }
    }
    func retryHandshake() {
        guard !editingKeymap else { return }
        testing = true
        state = nil; lastResponse = nil; pendingLayer = nil; pendingSince = nil
        handshakeAttempts = 0
        onChange?()
        if sending { retryPending = true } else { query() }
    }
    func close() {
        guard opened else { return }
        opened = false; editingKeymap = false
        finishVIA(.failure(VIAError.message("Keyboard disconnected. Any applied keys remain on the device; reconnect and reload.")))
        IOHIDDeviceCancel(device)
        IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        state = nil; pendingLayer = nil; pendingSince = nil; retryPending = false
    }
    func beginKeymapSession() async throws {
        guard opened, keymapProfile != nil, !editingKeymap else { throw VIAError.message("Connect the supported keyboard by USB and finish any active operation.") }
        editingKeymap = true
        let deadline = Date().addingTimeInterval(2)
        do {
            while sending {
                try Task.checkCancellation()
                guard opened, Date() < deadline else { throw VIAError.message("Keyboard busy. Try loading again.") }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch { editingKeymap = false; throw error }
    }
    func endKeymapSession() { editingKeymap = false; if opened { query() } }
    func exchangeVIA(_ packet: [UInt8]) async throws -> [UInt8] {
        guard opened, editingKeymap, pendingVIA == nil, packet.count == 32, VIAProtocol.commands.contains(packet[0]) else {
            throw VIAError.message("Invalid or overlapping VIA request.")
        }
        let deadline = Date().addingTimeInterval(2)
        while sending {
            try Task.checkCancellation()
            guard opened, Date() < deadline else { throw VIAError.message("Keyboard stopped responding.") }
            try await Task.sleep(for: .milliseconds(5))
        }
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            let pending = PendingVIAReply(packet: packet, continuation: continuation)
            pendingVIA = pending
            pending.timeout = Task { [weak self, weak pending] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, let pending, self.pendingVIA === pending else { return }
                self.finishVIA(.failure(VIAError.message("VIA reply timed out. Reload before retrying.")))
            }
            if !send(packet) { finishVIA(.failure(VIAError.message("Could not send the VIA request."))) }
        }
    }
    private func finishVIA(_ result: Result<[UInt8], any Error>) {
        guard let pending = pendingVIA else { return }
        pendingVIA = nil; pending.timeout?.cancel(); pending.continuation.resume(with: result)
    }
    deinit { buffer.deallocate() }
}

@MainActor final class LayerBridge {
    private var manager: IOHIDManager?
    private(set) var connections: [String: LayerConnection] = [:]
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var enabled: Bool { manager != nil }
    func start() {
        guard manager == nil else { return }
        // Connections own their report callbacks and scheduling. Prevent the
        // manager from also opening/scheduling each device behind their backs.
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(IOHIDManagerOptions.independentDevices.rawValue))
        // Only QMK Raw HID interfaces; never match generic keyboard or mouse reports.
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: 0xff60, kIOHIDDeviceUsageKey: 0x61] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            onError?("Could not open QMK Raw HID interfaces (\(result)). Allow Vehla in Input Monitoring if macOS requests it.")
            return
        }
        self.manager = manager; refresh()
    }
    func refresh(queryExisting: Bool = true) {
        guard let manager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        var present = Set<String>()
        let previousIDs = Set(connections.keys)
        for device in devices {
            var registryID: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID) == KERN_SUCCESS else { continue }
            let id = "rawhid.\(registryID)"; present.insert(id)
            if let existing = connections[id] { if queryExisting { existing.query() }; continue }
            let connection = LayerConnection(device: device, id: id)
            connection.onChange = { [weak self] in self?.onChange?() }
            connection.onError = { [weak self] in self?.onError?($0) }
            connections[id] = connection
            if !connection.open() { connections.removeValue(forKey: id); onError?("Could not open \(connection.name)’s Raw HID interface.") }
        }
        for id in Array(connections.keys) where !present.contains(id) { connections.removeValue(forKey: id)?.close() }
        if previousIDs != Set(connections.keys) { onChange?() }
    }
    func stop() {
        for connection in connections.values { connection.close() }; connections.removeAll()
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil; onChange?()
    }
    func testConnections() {
        refresh(queryExisting: false)
        for connection in connections.values { connection.retryHandshake() }
    }
}

// Retain packet storage until the asynchronous IOKit completion; never retain the
// connection here, so disabling the widget cannot create a callback ownership cycle.
private final class PendingHIDReport {
    let bytes: UnsafeMutablePointer<UInt8>
    @MainActor weak var connection: LayerConnection?
    @MainActor init(packet: [UInt8], connection: LayerConnection) {
        bytes = .allocate(capacity: packet.count)
        for (index, byte) in packet.enumerated() { bytes[index] = byte }
        self.connection = connection
    }
    deinit { bytes.deallocate() }
}

@MainActor private final class PendingVIAReply {
    let packet: [UInt8]
    let continuation: CheckedContinuation<[UInt8], any Error>
    var timeout: Task<Void, Never>?
    init(packet: [UInt8], continuation: CheckedContinuation<[UInt8], any Error>) {
        self.packet = packet; self.continuation = continuation
    }
}
