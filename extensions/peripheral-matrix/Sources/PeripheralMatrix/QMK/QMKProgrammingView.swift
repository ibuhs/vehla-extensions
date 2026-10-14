import SwiftUI
import VehlaDockWidgetSDK

struct QMKProgrammingView: View {
    @ObservedObject var model: PeripheralMatrixModel
    @State private var showDetails = false
    @State private var showNames = false
    @State private var showBridgeSetup = false
    private var connection: LayerConnection? { model.layers.first { $0.id == model.editorConnectionID } }
    private var canReload: Bool { !model.editor.busy && model.editor.changes.isEmpty }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("Keyboard Programming", systemImage: "keyboard").font(.title3.bold())
                Spacer()
                if model.layers.filter({ $0.keymapProfile != nil }).count > 1 {
                    Menu("Keyboard") {
                        ForEach(model.layers.filter { $0.keymapProfile != nil }) { keyboard in
                            Button(keyboard.name) { model.loadKeymap(keyboard) }
                        }
                    }.disabled(!canReload)
                }
                Button(action: {
                    if let connection { model.loadKeymap(connection) } else { model.refresh() }
                }) { Image(systemName: "arrow.clockwise") }
                    .disabled(!canReload).help("Reload current keyboard mapping")
                    .accessibilityLabel("Reload keyboard").accessibilityIdentifier("qmk.reload-keymap")
                Menu {
                    Button("Live layer setup and AI prompt…") { showBridgeSetup = true }
                    Button("Rename layers…") { showNames = true }.disabled(connection == nil)
                    Button("Test connection") { model.testBridge(); showDetails = true }.disabled(model.editor.busy)
                    Button("Supported keyboards and diagnostics…") { showDetails = true }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Programming options").accessibilityLabel("Programming options")
                    .popover(isPresented: $showDetails) { details.padding(20).frame(width: 380) }
            }
            if let profile = model.editor.profile, model.editor.baseline != nil {
                HStack {
                    Picker("Editing layer", selection: Binding(get: { model.editor.selectedLayer }, set: { model.editor.selectedLayer = $0 })) {
                        ForEach(0..<profile.layers, id: \.self) { layer in
                            Text(model.editorLayerNames[layer]).tag(layer)
                        }
                    }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Editing layer")
                        .accessibilityIdentifier("qmk.edit-layer")
                        .disabled(model.editor.busy).frame(maxWidth: 550)
                    Spacer(minLength: 12)
                    if let connection, let state = connection.state {
                        Menu {
                            ForEach(0..<Int(state.count), id: \.self) { layer in
                                Button(model.name(connection, layer: UInt8(layer))) { connection.select(UInt8(layer)) }
                                    .disabled(state.active == UInt8(layer))
                            }
                        } label: {
                            Label("Active: \(model.name(connection, layer: state.active))", systemImage: "checkmark.circle")
                        }.disabled(model.editor.busy || connection.pendingLayer != nil)
                            .help("Switch the keyboard's active layer. Editing a layer does not activate it.")
                    } else {
                        Button("Set up live layer control") { showBridgeSetup = true }
                            .font(.caption).accessibilityIdentifier("qmk.bridge.setup")
                    }
                }.padding(10).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                Text(connection?.name ?? model.editor.profile?.name ?? "Connect your keyboard")
                    .font(.headline).accessibilityIdentifier("qmk.connected-keyboard")
                Spacer()
                if model.editor.baseline != nil && !model.editor.needsReload {
                    Label("USB connected", systemImage: "circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            .popover(isPresented: $showNames) {
                if let connection {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Layer names").font(.headline)
                        ForEach(0..<4, id: \.self) { layer in
                            TextField("Layer \(layer)", text: Binding(get: { model.name(connection, layer: UInt8(layer)) },
                                set: { model.rename(connection, layer: UInt8(layer), name: $0) }))
                        }
                        Button("Done") { showNames = false }
                    }.padding(20).frame(width: 280)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    if model.editor.profile != nil {
                        QMKLayerEditorView(editor: model.editor, layerNames: model.editorLayerNames) {
                            if let connection { model.loadKeymap(connection) }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "keyboard").font(.system(size: 38)).foregroundStyle(.secondary)
                            Text("Ready when you connect").font(.headline)
                            Text("Plug a supported keyboard directly into your Mac in Cable mode. Its layout and current mapping load automatically.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                            if !model.layers.isEmpty {
                                Text("The connected keyboard has no verified programming layout.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 48)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.editor.baseline != nil {
                Divider()
                QMKEditorToolbarView(editor: model.editor, layerNames: model.editorLayerNames)
            }
        }.padding(24)
        .foregroundStyle(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .tint(Color(nsColor: model.theme?.primaryTextColor ?? .labelColor))
        .sheet(isPresented: $showBridgeSetup) { QMKBridgeSetupView() }
        .environment(\.colorScheme, model.theme?.isDark == true ? .dark : .light)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyboard connection").font(.headline)
            Text("Discovery is always enabled while this window is open. Programming reads VIA over USB. Switching the active layer requires VHLA bridge firmware.")
            Text("Supported: K10 Pro ANSI White; Q1 Max ANSI/ISO/JIS; V1–V6 ANSI, including knob variants where available. VIA protocol 12 and four firmware layers are required.")
            Text("Satechi SM1 has no VIA programming support. Knob rotation, lighting, and macro sequences are preserved rather than edited.")
            if let result = model.bridgeTestResult { Divider(); Text(result).textSelection(.enabled).accessibilityIdentifier("peripheral.bridge.test-result") }
        }.font(.caption)
    }
}
