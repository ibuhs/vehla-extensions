import SwiftUI

struct QMKLayerEditorView: View {
    @ObservedObject var editor: QMKEditorModel
    let layerNames: [String]
    let reload: () -> Void
    @State private var search = ""
    @State private var input = ""
    @State private var shortcutBase: UInt16 = 0x06 // C
    @State private var control = false
    @State private var shift = false
    @State private var option = false
    @State private var command = true
    @State private var action = "MO"
    @State private var targetLayer = 1
    private var selectedLabel: String { editor.selectedKey.map { QMKKeycodes.label(editor.code(for: $0), profile: editor.profile) } ?? "Select a key" }
    private func name(_ layer: Int) -> String { layerNames.indices.contains(layer) ? layerNames[layer] : "Layer \(layer)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Program layers", systemImage: "keyboard.badge.ellipsis").font(.headline)
                Spacer()
                Button("Reload", action: reload).disabled(editor.busy || !editor.changes.isEmpty)
                    .accessibilityIdentifier("qmk.reload-keymap")
            }
            if let status = editor.status {
                HStack(spacing: 8) {
                    if editor.busy { ProgressView().controlSize(.small) }
                    Text(status).font(.caption).textSelection(.enabled)
                }.accessibilityIdentifier("qmk.editor-status")
            }
            if let profile = editor.profile, editor.baseline != nil {
                Picker("Editing layer", selection: $editor.selectedLayer) {
                    ForEach(0..<profile.layers, id: \.self) { Text(name($0)).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("qmk.edit-layer")
                    .disabled(editor.busy)
                keyboard(profile)
                if let key = editor.selectedKey {
                    HStack {
                        Text("Selected: \(selectedLabel)").font(.headline)
                        Spacer()
                        Text("Row \(key / profile.columns), column \(key % profile.columns)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    assignments
                }
                if !editor.changes.isEmpty {
                    DisclosureGroup("Review \(editor.changes.count) changed assignments") {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(editor.changes) { change in
                                    let layer = change.index / profile.keysPerLayer
                                    let key = change.index % profile.keysPerLayer
                                    Text("\(name(layer)) · R\(key / profile.columns) C\(key % profile.columns): \(QMKKeycodes.label(change.before, profile: editor.profile)) → \(QMKKeycodes.label(change.after, profile: editor.profile))")
                                        .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.frame(maxHeight: 140)
                    }
                }
                Text("Edits change the draft only. Apply saves to the keyboard and survives reconnects. Editing a layer does not activate it. Firmware provides \(profile.layers) layers; adding more requires a firmware build.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { input = String(format: "0x%04X", editor.selectedKey.map { editor.code(for: $0) } ?? 0) }
        .onChange(of: editor.baseline?.captured) { _, _ in input = String(format: "0x%04X", editor.selectedKey.map { editor.code(for: $0) } ?? 0) }
        .onChange(of: editor.selectedKey) { _, _ in input = String(format: "0x%04X", editor.selectedKey.map { editor.code(for: $0) } ?? 0) }
        .onChange(of: editor.selectedLayer) { _, _ in input = String(format: "0x%04X", editor.selectedKey.map { editor.code(for: $0) } ?? 0) }
    }
    private func keyboard(_ profile: QMKKeyboardProfile) -> some View {
        GeometryReader { geometry in
            let unit = geometry.size.width / profile.layoutWidth
            ZStack(alignment: .topLeading) {
                ForEach(profile.keys) { key in
                    let changed = editor.changes.contains { $0.index == editor.selectedLayer * profile.keysPerLayer + key.id }
                    Button { editor.selectedKey = key.id } label: {
                        Text(QMKKeycodes.label(editor.code(for: key.id), profile: editor.profile)).font(.system(size: 8, weight: .medium))
                            .lineLimit(2).minimumScaleFactor(0.65)
                            .frame(width: max(8, key.width * unit - 3), height: max(8, key.height * unit - 3))
                            .background(editor.selectedKey == key.id ? Color.primary.opacity(0.2) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(changed ? Color.orange : Color.primary.opacity(0.12), lineWidth: changed ? 1.5 : 0.5))
                    }.buttonStyle(.plain)
                        .offset(x: key.x * unit, y: key.y * unit)
                        .accessibilityLabel("\(QMKKeycodes.label(editor.code(for: key.id), profile: editor.profile)), row \(key.row), column \(key.column)")
                        .accessibilityIdentifier("qmk.key.\(key.row).\(key.column)")
                        .disabled(editor.busy || editor.needsReload)
                }
            }
        }.aspectRatio(profile.layoutWidth / profile.layoutHeight, contentMode: .fit)
    }
    private var assignments: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Search keys, media, modifiers or existing macros", text: $search)
                TextField("KC_A or 0x0004", text: $input).frame(width: 125)
                    .accessibilityIdentifier("qmk.keycode-input")
                Button("Assign") { if let code = QMKKeycodes.parse(input, profile: editor.profile) { editor.assign(code) } }
                    .disabled(QMKKeycodes.parse(input, profile: editor.profile) == nil)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 5) {
                    ForEach(QMKKeycodes.options(for: editor.profile).filter { !(0x7700...0x777f).contains($0.code) || Int($0.code - 0x7700) < (editor.baseline?.macroCount ?? 0) }.filter { search.isEmpty ? $0.code <= 1 || (4...39).contains($0.code) : $0.name.localizedCaseInsensitiveContains(search) || $0.label.localizedCaseInsensitiveContains(search) }) { key in
                        Button(key.label) { editor.assign(key.code); input = String(format: "0x%04X", key.code) }
                            .controlSize(.small).help(key.name)
                    }
                }
            }.scrollIndicators(.visible)
            HStack {
                Text("Shortcut").font(.caption).frame(width: 60, alignment: .leading)
                Toggle("⌃", isOn: $control).toggleStyle(.button).help("Control")
                Toggle("⇧", isOn: $shift).toggleStyle(.button).help("Shift")
                Toggle("⌥", isOn: $option).toggleStyle(.button).help("Option")
                Toggle("⌘", isOn: $command).toggleStyle(.button).help("Command")
                Picker("Key", selection: $shortcutBase) {
                    ForEach(QMKKeycodes.basic.filter { (4...0x73).contains($0.code) }) { Text($0.label).tag($0.code) }
                }.labelsHidden().frame(width: 100)
                Spacer()
                Button("Assign shortcut") {
                    let mask: UInt16 = (control ? 1 : 0) | (shift ? 2 : 0) | (option ? 4 : 0) | (command ? 8 : 0)
                    if let code = QMKKeycodes.shortcut(shortcutBase, modifiers: mask) { editor.assign(code); input = String(format: "0x%04X", code) }
                }
            }.controlSize(.small)
            HStack {
                Text("Layer key").font(.caption).frame(width: 60, alignment: .leading)
                Picker("Action", selection: $action) {
                    Text("Hold (MO)").tag("MO")
                    Text("Toggle (TG)").tag("TG")
                    Text("Move (TO)").tag("TO")
                    Text("One shot (OSL)").tag("OSL")
                    Text("Default (DF)").tag("DF")
                }.labelsHidden().frame(width: 130)
                Picker("Target", selection: $targetLayer) {
                    ForEach(0..<(editor.profile?.layers ?? 4), id: \.self) { Text(name($0)).tag($0) }
                }.labelsHidden().frame(width: 130)
                Spacer()
                Button("Assign layer key") {
                    if let code = QMKKeycodes.layerAction(action, layer: targetLayer, count: editor.profile?.layers ?? 0) { editor.assign(code); input = String(format: "0x%04X", code) }
                }
            }.controlSize(.small)
        }.disabled(editor.busy || editor.needsReload)
    }
}

struct QMKEditorToolbarView: View {
    @ObservedObject var editor: QMKEditorModel
    let layerNames: [String]
    @State private var confirmApply = false
    private func name(_ layer: Int) -> String { layerNames.indices.contains(layer) ? layerNames[layer] : "Layer \(layer)" }
    var body: some View {
        HStack {
            Menu("Layer tools") {
                ForEach(0..<(editor.profile?.layers ?? 0), id: \.self) { source in
                    if source != editor.selectedLayer {
                        Button("Copy from \(name(source))") { editor.copyLayer(from: source) }.disabled(editor.needsReload)
                    }
                }
                Divider()
                Button("Import layer…", action: editor.importLayer).disabled(editor.needsReload)
                Button("Export layer…") { editor.exportLayer(name: name(editor.selectedLayer)) }
                Divider()
                Button("Restore backup into draft…", action: editor.restoreBackup).disabled(editor.needsReload)
                Button("Show backups", action: editor.showBackups)
            }.disabled(editor.busy)
            Spacer()
            Button("Discard draft", action: editor.discard).disabled(editor.busy || editor.changes.isEmpty)
            Button("Apply \(editor.changes.count) changes") { confirmApply = true }
                .disabled(!editor.canApply).accessibilityIdentifier("qmk.apply-keymap")
        }
        .alert("Save \(editor.changes.count) key assignments?", isPresented: $confirmApply) {
            Button("Cancel", role: .cancel) {}
            Button("Apply to keyboard", action: editor.apply)
        } message: {
            Text("A private backup is saved first. Only changed key assignments are written and verified. Existing macros are preserved.")
        }
    }
}
