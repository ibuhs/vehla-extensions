import SwiftUI
import VehlaDockWidgetSDK

struct PeripheralMatrixView: View {
    let surface: VehlaDockWidgetSurface
    @ObservedObject var model: PeripheralMatrixModel
    private var tileColor: Color { Color(nsColor: model.theme?.tileTextColor ?? .labelColor) }
    var body: some View {
        Group {
            switch surface {
            case .compact:
                VStack(spacing: 4) {
                    Image(systemName: model.dockIcon).font(.title2)
                        .accessibilityLabel(model.lowestPeripheral.map { "\($0.name), lowest battery" } ?? "Peripherals")
                    Text(model.lowestBattery.map { "\($0)%" } ?? "Devices").font(.system(size: 10, weight: .semibold))
                }.foregroundStyle(tileColor).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .inline:
                HStack {
                    Image(systemName: model.dockIcon)
                        .accessibilityLabel(model.lowestPeripheral.map { "\($0.name), lowest battery" } ?? "Peripherals")
                    Text("\(model.devices.count) devices").lineLimit(1)
                    Spacer()
                    Text(model.lowestBattery.map { "Low: \($0)%" } ?? "Battery —").monospacedDigit()
                }.font(.caption).foregroundStyle(tileColor).padding(10)
            case .popup: popup
            @unknown default: EmptyView()
            }
        }.tint(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .environment(\.colorScheme, model.theme?.isDark == true ? .dark : .light)
    }
    private var popup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Peripheral Matrix", systemImage: "keyboard").font(.title2.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh).labelStyle(.iconOnly)
                    .disabled(model.editor.busy)
            }
            Picker("Section", selection: $model.selectedTab) {
                ForEach(PeripheralMatrixTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Devices and QMK").accessibilityIdentifier("peripheral.tabs")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    if model.selectedTab == .devices { devicesTab } else { qmkTab }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.selectedTab == .qmk, model.editor.baseline != nil {
                Divider()
                QMKEditorToolbarView(editor: model.editor, layerNames: model.editorLayerNames)
            }
        }.padding(20).foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
    }
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
                GroupBox("Battery overview") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.devices.isEmpty { Text("No wireless input devices publish battery data on this Mac.").foregroundStyle(.secondary) }
                        ForEach(model.devices) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.icon).font(.title3).frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.headline)
                                    Text(device.transport).font(.caption).foregroundStyle(.secondary)
                                    if let battery = device.battery { ProgressView(value: Double(battery), total: 100).tint(battery <= 20 ? .orange : .green) }
                                }
                                Spacer()
                                Text(device.batteryText).monospacedDigit().foregroundStyle(device.battery.map { $0 <= 20 } == true ? Color.orange : Color.primary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                Toggle("Discover Bluetooth LE batteries", isOn: Binding(get: { model.bluetoothEnabled }, set: model.setBluetooth))
                Text("Connects to devices exposing the standard Battery Service. Matching device status and battery readings are combined into one row. Connected headphones show battery readings when macOS reports them.")
                    .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var qmkTab: some View {
        VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keymap layers").font(.headline)
                    Spacer()
                    Button(model.editingProfiles ? "Done" : "Rename profiles") { model.editingProfiles.toggle() }
                }
                Toggle("Connect QMK firmware bridge", isOn: Binding(get: { model.bridgeEnabled }, set: model.setBridge))
                    .accessibilityIdentifier("peripheral.bridge.enabled")
                    .disabled(model.editor.busy)
                Button("Test bridge", action: model.testBridge)
                    .disabled(!model.bridgeEnabled || model.editor.busy)
                    .accessibilityIdentifier("peripheral.bridge.test")
                    .accessibilityHint("Reconnect and check the keyboard’s live layer reply without changing its keymap.")
                if let result = model.bridgeTestResult {
                    DisclosureGroup("Bridge diagnostics") {
                        Text(result).font(.caption).textSelection(.enabled)
                            .accessibilityIdentifier("peripheral.bridge.test-result")
                    }
                }
                Text("Live switching requires the VHLA firmware bridge. Programming uses VIA over USB on the supported K10 Pro ANSI White; no firmware flash is needed.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.bridgeEnabled && model.layers.isEmpty { Text("No QMK Raw HID interfaces found.").font(.caption).foregroundStyle(.secondary) }
                ForEach(model.layers) { connection in
                    if model.editorConnectionID == connection.id, model.editor.baseline != nil, !model.editingProfiles {
                        DisclosureGroup("\(connection.name) · Active: \(connection.state.map { model.name(connection, layer: $0.active) } ?? "Unknown")") { layerCard(connection) }
                    } else { layerCard(connection) }
                }
            if model.editor.profile != nil {
                Divider()
                QMKLayerEditorView(editor: model.editor, layerNames: model.editorLayerNames) {
                    if let connection = model.layers.first(where: { $0.id == model.editorConnectionID }) { model.loadKeymap(connection) }
                }
            }
        }
    }
    private func layerCard(_ connection: LayerConnection) -> some View {
        GroupBox(connection.name) {
            VStack(alignment: .leading, spacing: 10) {
                if connection.keymapProfile != nil {
                    Button(model.editorConnectionID == connection.id ? "Load / reload keymap" : "Program layers") { model.loadKeymap(connection) }
                        .disabled(model.editor.busy || !model.editor.changes.isEmpty)
                        .accessibilityIdentifier("qmk.load-keymap")
                } else {
                    Text("Layer switching is available for supported bridge firmware. The keymap editor currently supports K10 Pro ANSI White.").font(.caption).foregroundStyle(.secondary)
                }
                if let state = connection.state {
                    Label("Active: \(model.name(connection, layer: state.active))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        .accessibilityIdentifier("peripheral.bridge.active.\(connection.id)")
                    if connection.pendingLayer != nil { ProgressView("Waiting for keyboard confirmation…").controlSize(.small) }
                    ForEach(0..<Int(state.count), id: \.self) { number in
                        let layer = UInt8(number)
                        HStack {
                            Text("\(number)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 20)
                            if model.editingProfiles {
                                TextField("Profile name", text: Binding(get: { model.name(connection, layer: layer) }, set: { model.rename(connection, layer: layer, name: $0) }))
                            } else { Text(model.name(connection, layer: layer)) }
                            Spacer()
                            Button(state.active == layer ? "Active" : "Switch") { connection.select(layer) }
                                .disabled(state.active == layer || connection.pendingLayer != nil || model.editor.busy)
                                .accessibilityLabel("Switch \(connection.name) to \(model.name(connection, layer: layer))")
                        }
                    }
                } else {
                    Text("Firmware bridge not confirmed. Use Test bridge to retry. USB and supported bridge firmware are required.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}
