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
                Label("Peripherals", systemImage: "keyboard").font(.headline)
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
        }.padding(18).foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
    }
    private var devicesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 0) {
                if model.devices.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard").font(.title2).foregroundStyle(.secondary)
                        Text("No battery readings yet").font(.headline)
                        Text("Connect a device or refresh to check again.").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 20)
                }
                ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, device in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: device.icon).font(.title3).frame(width: 24).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(device.batteryText).font(.caption).monospacedDigit()
                                    .foregroundStyle(device.battery.map { $0 <= 20 } == true ? Color.orange : Color.primary)
                            }
                            Text(device.transport).font(.caption2).foregroundStyle(.secondary)
                            if let battery = device.battery {
                                ProgressView(value: Double(battery), total: 100).tint(battery <= 20 ? .orange : .green)
                            }
                        }
                    }.padding(12).accessibilityElement(children: .combine)
                    if index < model.devices.count - 1 { Divider().padding(.leading, 48).padding(.trailing, 12) }
                }
            }.background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            Toggle("Bluetooth battery discovery", isOn: Binding(get: { model.bluetoothEnabled }, set: model.setBluetooth))
                .font(.caption).help("Reads supported Bluetooth batteries and AirPods readings supplied by macOS.")
        }
    }
}
