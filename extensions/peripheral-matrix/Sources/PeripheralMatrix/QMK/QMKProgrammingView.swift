import SwiftUI
import VehlaDockWidgetSDK

struct QMKProgrammingView: View {
    @ObservedObject var model: PeripheralMatrixModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("QMK Keyboard Programming", systemImage: "keyboard").font(.title2.bold())
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: model.refresh)
                    .labelStyle(.iconOnly).disabled(model.editor.busy)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                    qmkTab
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.editor.baseline != nil {
                Divider()
                QMKEditorToolbarView(editor: model.editor, layerNames: model.editorLayerNames)
            }
        }.padding(24)
        .foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .tint(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .environment(\.colorScheme, model.theme?.isDark == true ? .dark : .light)
    }
    private var qmkTab: some View {
        VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Keymap layers").font(.headline)
                    Spacer()
                    Button(model.editingProfiles ? "Done" : "Rename profiles") { model.editingProfiles.toggle() }
                }
                Toggle("Connect programmable keyboards", isOn: Binding(get: { model.bridgeEnabled }, set: model.setBridge))
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
                Text("Live switching requires the VHLA firmware bridge. Programming uses VIA over USB on recognized keyboards; no bridge flash is needed to edit keys.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Supported keyboards") {
                    Text("K10 Pro ANSI White · Q1 Max ANSI/ISO/JIS · V1–V6 ANSI, including knob variants where available. USB Cable mode and VIA protocol 12 are required. Other firmware versions are rejected before writes. Knob rotation and lighting are preserved, not edited.").font(.caption).foregroundStyle(.secondary)
                    Text("Satechi SM1 does not support VIA programming; battery status remains available when the device publishes it.").font(.caption).foregroundStyle(.secondary)
                }
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
                    Text("Layer switching is available for supported bridge firmware. No verified layout is available for this keyboard.").font(.caption).foregroundStyle(.secondary)
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
                    Text("Live layer switching requires VHLA bridge firmware. Recognized VIA keyboards can use Program layers without that bridge.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }
}
