import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VehlaDockWidgetSDK

struct QuickNoteRootView: View {
    let surface: VehlaDockWidgetSurface
    @ObservedObject var model: QuickNoteModel
    var body: some View {
        switch surface {
        case .compact:
            VStack(spacing: 3) {
                Image(systemName: model.autoPaste ? "clipboard.fill" : "note.text").font(.system(size: 18, weight: .semibold))
                Text(model.notes.isEmpty ? "Notes" : "\(model.notes.count)").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(Color(nsColor: model.tileTextColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help(model.autoPaste ? "AutoPaste is collecting copies into \(model.selected?.title ?? "a note")" : model.selected?.title ?? "Your scratchpad")
        case .inline:
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selected?.title ?? "Scratchpad").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(model.selected?.preview ?? "A little room to think").font(.system(size: 9)).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 0)
                if model.autoPaste { Image(systemName: "clipboard.fill").help("AutoPaste is on") }
            }
            .foregroundStyle(Color(nsColor: model.tileTextColor)).padding(.horizontal, 10)
        case .popup: PopupNoteView(model: model)
        @unknown default: EmptyView()
        }
    }
}

private struct PopupNoteView: View {
    @ObservedObject var model: QuickNoteModel
    @FocusState private var searchFocused: Bool
    private var primary: Color { Color(nsColor: model.editorTextColor) }
    private var secondary: Color { Color(nsColor: model.theme?.secondaryTextColor ?? .secondaryLabelColor) }
    private var accent: Color { Color(nsColor: model.theme?.accentColor ?? .controlAccentColor) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                if model.sidebar || model.scope == "void" {
                    noteList.frame(width: 230)
                    Divider()
                }
                paper
            }
            Divider()
            footer
            if let status = model.status {
                HStack(alignment: .top) {
                    Text(status).font(.system(size: 11)).foregroundStyle(model.statusIsError ? .orange : secondary)
                    Spacer(minLength: 4)
                    Button { model.status = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
                }.padding(.horizontal, 14).padding(.vertical, 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(primary)
        .background(Color.clear)
        .sheet(isPresented: $model.importPresented) { ImportNotesView(model: model) }
        .confirmationDialog("Move this note to The Void?", isPresented: $model.deletePresented) {
            Button("Move to The Void") { model.trash() }
        } message: { Text("You can restore it from the Void tab.") }
        .confirmationDialog("Recover the previous saved library?", isPresented: $model.recoverPresented) {
            Button("Recover Previous Save") { model.recover() }
        } message: { Text("The previous library replaces the current one. Export a backup first if you want to keep both.") }
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                model.sidebar.toggle(); if model.sidebar { searchFocused = true }
            } label: { Image(systemName: "magnifyingglass") }
            .help("Search notes (⌘F)").keyboardShortcut("f", modifiers: .command)
            Text("QuickNote").font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { model.navigate(1) } label: { Image(systemName: "chevron.left") }.help("Older note (⌘[)")
                .keyboardShortcut("[", modifiers: .command).disabled(!model.ready)
            Button { model.navigate(-1) } label: { Image(systemName: "chevron.right") }.help("Newer note (⌘])")
                .keyboardShortcut("]", modifiers: .command).disabled(!model.ready)
            Button { model.startNewNote() } label: { Image(systemName: "square.and.pencil") }.help("New note (⌘N)")
                .keyboardShortcut("n", modifiers: .command).disabled(!model.ready)
            Menu {
                Button("Math Reference…") { model.mathReference.show(model: model) }
                Menu("Math Result Color") {
                    ForEach(MathResultColor.allCases, id: \.self) { color in
                        Button {
                            model.settings(mathColor: color)
                        } label: {
                            if (model.library.mathResultColor ?? .automatic) == color {
                                Label(color.title, systemImage: "checkmark")
                            } else { Text(color.title) }
                        }
                    }
                }.disabled(!model.ready)
                Menu("Math 108X Examples") {
                    ForEach(CourseMathExamples.all, id: \.title) { example in
                        Button(example.title) { model.startNewNote(content: example.content) }
                    }
                }.disabled(!model.ready)
                Button("Import Notes…") { model.beginImport() }.disabled(!model.ready)
                Button("Export Text…") { model.export() }.keyboardShortcut("s", modifiers: .command).disabled(!model.ready || model.selected == nil)
                Button("Export Markdown…") { model.export(markdown: true) }.disabled(!model.ready || model.selected == nil)
                Button("Export Library Backup…") { model.export(backup: true) }.disabled(!model.ready)
                Button("Send to Vehla Notes") { model.sendToNotes() }.disabled(model.context?.app == nil || model.selected == nil)
                Divider()
                Button("Open Note in Window") { model.popOut() }.keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.selected == nil || model.selected?.deleted != nil)
                Button("Swap Stack / Slots") { _ = model.perform(shortcut: "swap") }.keyboardShortcut("t", modifiers: .command)
                Button(model.autoPaste ? "Stop AutoPaste" : "Start AutoPaste") { _ = model.command("/paste") }
                    .disabled(!model.autoPaste && (model.selected == nil || model.selected?.deleted != nil))
                Button("Find and Replace") { _ = model.perform(shortcut: "find") }.keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(model.selected == nil || model.selected?.deleted != nil)
                Button("Promote to Front") { model.promote() }.keyboardShortcut("1", modifiers: [.command, .shift])
                    .disabled(model.selected == nil || model.selected?.slot != nil || model.selected?.deleted != nil)
                Button("Move to The Void…") { model.deletePresented = true }.keyboardShortcut("d", modifiers: .command).disabled(model.selected == nil || model.selected?.slot != nil || model.selected?.deleted != nil)
                Divider()
                Toggle("Lined Paper", isOn: Binding(get: { model.library.linedPaper }, set: { model.settings(lined: $0) }))
                Menu("Expire Unmodified Scratch Notes") {
                    ForEach([0, 1, 7, 30, 365], id: \.self) { days in
                        Button(days == 0 ? "Never" : "After \(days) days") { model.settings(expiry: days) }
                    }
                }
                Button("Larger Text") { model.settings(fontSize: model.library.fontSize + 1) }.keyboardShortcut("+", modifiers: .command)
                Button("Smaller Text") { model.settings(fontSize: model.library.fontSize - 1) }.keyboardShortcut("-", modifiers: .command)
                Divider()
                Button("Recover Previous Save…") { model.recoverPresented = true }
                Button("Save Now") { model.saveCurrent() }.disabled(!model.ready)
            } label: { Image(systemName: "ellipsis.circle") }.help("Import, export and settings")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var noteList: some View {
        VStack(spacing: 10) {
            TextField("Search your notes", text: $model.query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .onSubmit {
                    if let first = model.visible.first { model.select(first.id) }
                    else if !model.query.isEmpty { model.startNewNote(content: model.query) }
                }
            ScopeTabs(model: model, primary: primary, secondary: secondary)
            ScrollView {
                let positions = model.stackPositions
                LazyVStack(spacing: 6) {
                    ForEach(model.visible) { note in
                        Button {
                            model.select(note.id); searchFocused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Spacer(minLength: 2)
                                    if let slot = note.slot {
                                        Label("\(slot)", systemImage: "pin.fill").labelStyle(.titleAndIcon)
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(secondary)
                                    } else if note.deleted == nil, let page = positions[note.id] {
                                        Text("\(page)").font(.system(size: 9, weight: .medium, design: .monospaced)).monospacedDigit()
                                            .foregroundStyle(secondary)
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(primary.opacity(0.08), in: Capsule())
                                            .help("Page \(page) of \(positions.count)")
                                    }
                                }
                                Text(note.preview).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10).background(note.id == model.selectedID ? accent.opacity(0.12) : secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                            .contextMenu {
                                if note.deleted != nil { Button("Restore") { model.restore(note.id) } }
                                else { Button("Open in Window") { model.popOut(note.id) } }
                                if note.deleted == nil, note.slot == nil {
                                    Button("Promote to Front") { model.promote(note.id) }
                                    Button("Move to The Void") { model.trash(note.id) }
                                }
                            }
                    }
                    if model.visible.isEmpty {
                        VStack(spacing: 10) {
                            Text(model.scope == "void" ? "The Void is quiet." : "No matching notes.").foregroundStyle(secondary)
                            if !model.query.isEmpty && model.scope != "void" {
                                Button("Create a note from search") { model.startNewNote(content: model.query) }
                            }
                        }.font(.system(size: 11)).padding(.top, 30)
                    }
                }
            }
            Text("\(model.visible.count) notes").font(.system(size: 10)).foregroundStyle(secondary)
        }.padding(10)
    }

    private var paper: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if !model.ready {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.title2)
                    Text("Your library could not be loaded.")
                    Button("Recover Previous Save") { model.recoverPresented = true }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.selected == nil {
                VStack(spacing: 12) {
                    Text("A little room to think.").font(.system(size: 23, weight: .light))
                    Button("Start a note") { model.startNewNote() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.findPresented { findBar }
                HStack {
                    Text(model.selected?.deleted != nil ? "THE VOID" : model.analysis.mode.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(primary)
                    Spacer()
                    if model.selected?.deleted != nil { Button("Restore Note") { if let id = model.selectedID { model.restore(id) } } }
                    else {
                        Button { model.popOut() } label: { Image(systemName: "macwindow.on.rectangle").font(.system(size: 11)) }
                            .buttonStyle(.borderless).help("Open in its own window (⌘⇧O)")
                        slotMenu
                    }
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                if model.selected?.deleted != nil {
                    ScrollView { Text(model.draft).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                } else {
                    InlineNoteEditor(text: model.draft, textColor: model.editorTextColor, autoFocus: true,
                                     onEdit: model.inlineEdited, onSave: model.saveCurrent,
                                     fontSize: model.library.fontSize, focusToken: model.focusToken,
                                     analysis: model.analysis, resultColor: model.library.mathResultColor ?? .automatic,
                                     onResultCopy: model.didCopyResult,
                                     linedPaper: model.library.linedPaper,
                                     onCommand: model.command, onShortcut: model.perform(shortcut:), onNavigate: model.navigate, onEscape: model.escape,
                                     onImage: { model.recognizeImage($0) }, onImageFile: { model.recognizeFile($0) },
                                     onOpenURL: { model.context?.open($0) })
                    .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                                if let url { Task { @MainActor in model.recognizeFile(url) } }
                            }
                        } else {
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                                if let data { Task { @MainActor in model.recognizeImage(data) } }
                            }
                        }
                        return true
                    }
                }
                if model.scope == "slots" {
                    HStack(spacing: 8) {
                        ForEach(1...9, id: \.self) { slot in
                            Button { model.jumpSlot(slot) } label: {
                                Text("\(slot)").font(.system(size: 11, design: .monospaced))
                                    .frame(width: 25, height: 25)
                                    .background(model.selected?.slot == slot ? accent.opacity(0.2) : secondary.opacity(0.07), in: Circle())
                            }.buttonStyle(.plain).help("Permanent slot \(slot)")
                        }
                    }.frame(maxWidth: .infinity).padding(.bottom, 12)
                }
                if model.stopwatchStart != nil || model.stopwatchPaused {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        HStack {
                            Image(systemName: "stopwatch")
                            Text(Duration.seconds(model.stopwatchElapsed + (model.stopwatchStart.map { timeline.date.timeIntervalSince($0) } ?? 0)).formatted(.time(pattern: .hourMinuteSecond)))
                                .monospacedDigit()
                            Button(model.stopwatchPaused ? "Resume" : "Pause") { model.toggleStopwatch() }
                            Button("Stop") { model.stopStopwatch() }
                        }.font(.system(size: 12)).padding(.horizontal, 24).padding(.bottom, 10)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var slotMenu: some View {
        Menu {
            Button("Keep in Scratch Stack") { model.setSlot(nil) }
            ForEach(1...9, id: \.self) { slot in Button("Keep in Slot \(slot)") { model.setSlot(slot) } }
        } label: {
            Label(model.selected?.slot.map { "Slot \($0)" } ?? "Keep", systemImage: model.selected?.slot == nil ? "pin" : "pin.fill")
                .font(.system(size: 11))
        }.menuStyle(.borderlessButton).fixedSize()
    }
    private var findBar: some View {
        HStack(spacing: 6) {
            TextField("Find", text: $model.findText)
            TextField("Replace", text: $model.replacement)
            Toggle("Aa", isOn: $model.caseSensitive).toggleStyle(.button)
            Button("Replace All", action: model.replaceAll).disabled(model.findText.isEmpty)
            Button { model.findPresented = false } label: { Image(systemName: "xmark") }
        }.textFieldStyle(.roundedBorder).font(.system(size: 11)).padding(10)
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Text(model.isDirty ? "Saving…" : "Saved on this Mac").font(.system(size: 10)).foregroundStyle(secondary)
            Spacer()
            if model.autoPaste {
                Button { model.stopCapture() } label: { Label("Stop AutoPaste", systemImage: "clipboard.fill") }.foregroundStyle(accent)
            } else {
                Text(model.analysis.summary).font(.system(size: 10)).foregroundStyle(secondary)
            }
            Button { model.copyDraft() } label: { Image(systemName: "doc.on.doc") }.help("Copy note").disabled(model.selected == nil)
            if let page = model.pageLabel {
                Text(page).font(.system(size: 10, design: .monospaced)).monospacedDigit().foregroundStyle(secondary)
                    .help("Position in your notes; ⌘[ and ⌘] turn the page")
            }
        }.buttonStyle(.borderless).font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 10)
    }
}

/// Stack / Slots / Void switcher in the widget's own colors, with counts.
struct ScopeTabs: View {
    @ObservedObject var model: QuickNoteModel
    let primary: Color
    let secondary: Color
    @Namespace private var selection

    private var tabs: [(id: String, title: String, symbol: String, count: Int)] {
        let active = model.notes
        return [
            ("stack", "Stack", "square.stack", active.filter { $0.slot == nil }.count),
            ("slots", "Slots", "pin", active.filter { $0.slot != nil }.count),
            ("void", "Void", "trash", model.library.notes.count - active.count),
        ]
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.id) { tab in
                let selected = model.scope == tab.id
                Button {
                    withAnimation(.snappy(duration: 0.22)) { model.scope = tab.id }
                } label: {
                    HStack(spacing: 3) {
                        Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                            .minimumScaleFactor(0.8)
                        if tab.count > 0 {
                            Text(tab.count > 999 ? "999+" : "\(tab.count)")
                                .font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(primary.opacity(selected ? 0.16 : 0.08), in: Capsule())
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 3)
                    .foregroundStyle(selected ? primary : secondary)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(primary.opacity(0.13))
                                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                                .matchedGeometryEffect(id: "tab", in: selection)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.id == "void" ? "Deleted notes you can restore" : tab.id == "slots" ? "Notes kept in permanent slots" : "Your scratch notes, newest first")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityLabel("\(tab.title), \(tab.count) notes")
            }
        }
        .padding(3)
        .background(primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct ImportNotesView: View {
    @ObservedObject var model: QuickNoteModel
    private var primary: Color { Color(nsColor: model.editorTextColor) }
    private var secondary: Color { Color(nsColor: model.theme?.secondaryTextColor ?? .secondaryLabelColor) }
    private var accent: Color { Color(nsColor: model.theme?.accentColor ?? .controlAccentColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Import Notes", systemImage: "square.and.arrow.down").font(.system(size: 13, weight: .semibold))
                Text("QUICKNOTE").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(secondary)
                Spacer()
                Button("Done") { model.cancelImport() }.keyboardShortcut(.cancelAction)
            }
            Divider()
            Text("Bring your scratch notes into Vehla.").font(.system(size: 12)).foregroundStyle(secondary)
            if model.importing { ProgressView("Looking for notes…").frame(maxWidth: .infinity, minHeight: 180) }
            else if let preview = model.importPreview {
                Text(preview.message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                if !preview.notes.isEmpty {
                    HStack {
                        Text("\(preview.notes.count) notes · \(preview.source)").font(.system(size: 11)).foregroundStyle(secondary)
                        Spacer()
                        Button("Select All") { model.selectAllImports() }
                        Button("None") { model.importSelection = [] }
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(preview.notes) { note in
                                let imported = model.isImported(note)
                                Toggle(isOn: Binding(get: { model.importSelection.contains(note.id) }, set: { checked in
                                    if checked { model.importSelection.insert(note.id) } else { model.importSelection.remove(note.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(note.title).lineLimit(1)
                                        Text(imported ? "Already imported — local edits are preserved" : note.preview).font(.system(size: 10)).foregroundStyle(secondary).lineLimit(1)
                                    }
                                }.disabled(imported)
                            }
                        }.padding(8)
                    }.frame(minHeight: 140, maxHeight: 280)
                }
            } else { Text("No import is ready. Choose a backup or exported files below.").foregroundStyle(secondary) }
            if let status = model.status, model.statusIsError {
                Text(status).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                Button("Open Full Disk Access Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { model.context?.open(url) }
                }
            }
            Divider()
            HStack {
                Button("Choose Files…") { model.chooseImportFiles() }.disabled(model.importing)
                Button("Scan Again") { model.beginImport() }.disabled(model.importing)
                Spacer()
                Button("Import \(model.importSelection.count) Notes") { model.confirmImport() }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .disabled(model.importing || model.importSelection.isEmpty || model.importPreview == nil)
            }
            Text("Accepts Antinote SQLite databases and backups, UTF-8 text, Markdown, and Vehla library JSON. Occupied slots import into the scratch stack.")
                .font(.system(size: 10)).foregroundStyle(secondary)
        }
        .font(.system(size: 12))
        .foregroundStyle(primary)
        .tint(accent)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(24).frame(width: 580)
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(model.theme.map { $0.isDark ? .dark : .light })
    }
}
