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
                Label("Peripheral Matrix", systemImage: "keyboard").font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh).labelStyle(.iconOnly)
                    .disabled(model.editor.busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    devicesTab
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            Button(action: model.openProgramming) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.badge.ellipsis")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QMK Keyboard Programming").font(.headline)
                        Text("Layers, shortcuts, and key assignments").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward").font(.caption)
                }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.plain).accessibilityIdentifier("peripheral.qmk.open")
            .accessibilityHint("Opens keyboard programming in a larger window.")
        }.padding(20).foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
    }
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 18) {
                GroupBox("Battery overview") {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.devices.isEmpty { Text("No battery readings yet. Connect a device or refresh to check again.").foregroundStyle(.secondary) }
                        ForEach(model.devices) { device in
                            HStack(spacing: 12) {
                                Image(systemName: device.icon).font(.title3).frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(device.name).font(.headline)
                                    Text(device.transport).font(.caption).foregroundStyle(.secondary)
                                    if let battery = device.battery { ProgressView(value: Double(battery), total: 100).tint(battery <= 20 ? .orange : .green) }
                                }
                                Spacer()
                                Text(device.batteryText).font(.caption).monospacedDigit().foregroundStyle(device.battery.map { $0 <= 20 } == true ? Color.orange : Color.primary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                Toggle("Discover Bluetooth LE batteries", isOn: Binding(get: { model.bluetoothEnabled }, set: model.setBluetooth))
                Text("Reads supported Bluetooth batteries. AirPods readings appear when macOS provides them.")
                    .font(.caption).foregroundStyle(.secondary)
        }
    }
}
