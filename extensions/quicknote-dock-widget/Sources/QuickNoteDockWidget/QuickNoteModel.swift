import AppKit
import Foundation
import UniformTypeIdentifiers
import VehlaDockWidgetSDK

@MainActor
final class QuickNoteModel: ObservableObject {
    @Published private(set) var library = ScratchLibrary()
    @Published private(set) var loading = true
    @Published private(set) var ready = false
    @Published var draft = ""
    @Published var query = "" { didSet { search() } }
    @Published var scope = "stack" { didSet { search() } }
    @Published private(set) var visible: [ScratchNote] = []
    @Published var status: String? {
        didSet {
            statusDismissTask?.cancel()
            statusDismissTask = nil
            guard status != nil, !statusIsError, !closed else { return }
            statusDismissTask = Task { [weak self, delay = statusDismissDelay] in
                do { try await Task.sleep(for: delay) } catch { return }
                guard !Task.isCancelled else { return }
                self?.status = nil
            }
        }
    }
    var statusDismissDelay: Duration = .seconds(3)
    private var statusDismissTask: Task<Void, Never>?
    @Published var statusIsError = false
    @Published var theme: VehlaDockWidgetTheme? {
        didSet { mathReference.updateAppearance(isDark: theme?.isDark); noteWindows.updateAppearance(isDark: theme?.isDark) }
    }
    @Published var importPresented = false
    @Published var importPreview: ImportPreview?
    @Published var importSelection: Set<String> = []
    /// Import keys of the current preview that this library already holds.
    @Published private(set) var importPresentKeys: Set<String> = []
    @Published var importing = false
    @Published var sidebar = false
    @Published var deletePresented = false
    @Published var recoverPresented = false
    @Published var findPresented = false
    @Published var findText = ""
    @Published var replacement = ""
    @Published var caseSensitive = false
    @Published var analysis = ScratchAnalysis()
    @Published var autoPaste = false
    @Published var stopwatchStart: Date?
    @Published var stopwatchElapsed: TimeInterval = 0
    @Published var stopwatchPaused = false
    @Published var focusToken = UUID()
    @Published private(set) var searchFocusRequest = 0
    private(set) var context: VehlaDockWidgetContext?
    private var repository: ScratchRepository?
    private let importer = ScratchImporter()
    private let tools = ScratchTools()
    let mathReference = MathReferenceWindow()
    let noteWindows = NoteWindows()
    /// Formatting for each popped-out note, kept apart from the dock editor's
    /// `analysis`, which follows the selection and pauses while it is hidden.
    @Published private(set) var poppedAnalyses: [String: ScratchAnalysis] = [:]
    private var poppedTasks: [String: Task<Void, Never>] = [:]
    private var loadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var replaceTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var presentations = ScratchPresentationStore()
    private var importTask: Task<Void, Never>?
    private var ocrTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var active = false
    private var closed = false
    private var pasteboardChange = 0
    /// The pasteboard AutoPaste reads; tests substitute a private one.
    var pasteboard = NSPasteboard.general
    private var pasteDelimiter = "\n"
    private var captureNoteID: String?
    /// Text this widget copied itself; AutoPaste must not append it back.
    private var ownCopy: String?
    private var savedRevision: UInt64 = 0

    var notes: [ScratchNote] { library.notes.filter { $0.deleted == nil } }
    var selectedID: String? { library.selectedID }
    var selected: ScratchNote? { library.notes.first { $0.id == selectedID } }
    var tileTextColor: NSColor { theme?.tileTextColor ?? .labelColor }
    var editorTextColor: NSColor { theme?.primaryTextColor ?? .labelColor }
    var isDirty: Bool { library.revision > savedRevision }

    /// 1-based place of each scratch note in the stack ⌘[ / ⌘] page through.
    var stackPositions: [String: Int] {
        var positions: [String: Int] = [:]
        for (index, note) in notes.lazy.filter({ $0.slot == nil }).enumerated() { positions[note.id] = index + 1 }
        return positions
    }

    /// "3 / 12" for the selected note's place in the stack that ⌘[ / ⌘] page
    /// through; slotted notes show their slot, and The Void shows nothing.
    var pageLabel: String? {
        guard let note = selected, note.deleted == nil else { return nil }
        if let slot = note.slot { return "Slot \(slot)" }
        let stack = notes.filter { $0.slot == nil }
        guard let index = stack.firstIndex(where: { $0.id == note.id }) else { return nil }
        return "\(index + 1) / \(stack.count)"
    }

    func configure(_ context: VehlaDockWidgetContext) {
        self.context = context; theme = context.theme; closed = false
        if repository == nil { repository = ScratchRepository(root: context.dataDirectory, legacyRoot: ScratchRepository.legacyDirectory(for: context.dataDirectory)) }
        start()
    }

    func start() {
        active = true
        if ready {
            let previous = library
            library.expire()
            if library != previous { changed() }
            ensureSelection(); search(); analyze(); return
        }
        guard loadTask == nil, let repository else { return }
        loading = true
        let tools = tools
        loadTask = Task { [weak self] in
            do {
                let state = try await repository.load()
                let initial = state.notes.first { $0.id == state.selectedID && $0.deleted == nil }
                    ?? state.notes.first { $0.deleted == nil }
                // Formatting is optional; it must never stop the library from opening.
                let prepared = if let initial { try? await tools.analyze(initial.content) } else { ScratchAnalysis?.none }
                guard let self, !Task.isCancelled, !self.closed else { return }
                if let initial, let prepared {
                    self.presentations.insert(prepared, for: initial.id)
                    self.analysis = prepared
                }
                self.library = state; self.savedRevision = state.revision; self.ready = true
                let previous = self.library
                self.library.expire()
                if self.library != previous { self.changed() }
                self.ensureSelection(); self.search(); self.analyze()
            } catch {
                // A cancelled load belongs to a closed instance; a newer load may own the state now.
                guard !Task.isCancelled else { return }
                self?.fail("Could not load notes: \(error.localizedDescription)")
            }
            self?.loading = false; self?.loadTask = nil
        }
    }

    func stop() {
        active = false
        // AutoPaste keeps collecting while the popup is closed: copying happens
        // in other apps, which closes it. Only the user, a note change or
        // unloading the widget turns it off.
        searchTask?.cancel(); analysisTask?.cancel(); replaceTask?.cancel(); preloadTask?.cancel(); preloadTask = nil; importTask?.cancel(); ocrTask?.cancel()
        importing = false; importPreview = nil; importPresented = false
        // Accepted writes must drain even when the surface disappears.
        debounceTask?.cancel()
        if ready, isDirty { persist() }
    }

    func close() {
        mathReference.close()
        noteWindows.closeAll()
        stopCapture(); stop(); closed = true; loadTask?.cancel(); loadTask = nil
        statusDismissTask?.cancel(); statusDismissTask = nil
        context = nil
    }

    private func changed() {
        library.revision += 1
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.persist()
        }
        search(); context?.invalidate()
    }

    private func persist() {
        guard ready, let repository, library.revision > savedRevision else { return }
        let snapshot = library
        // Chain accepted snapshots so a close flush cannot race an earlier edit.
        let previous = saveTask
        saveTask = Task { [weak self] in
            await previous?.value
            do {
                try await repository.save(snapshot)
                guard let self else { return }
                self.savedRevision = max(self.savedRevision, snapshot.revision)
            } catch { self?.fail("Save failed; your edits are still in memory. \(error.localizedDescription)") }
        }
    }

    func saveCurrent() { debounceTask?.cancel(); persist() }

    private func ensureSelection() {
        let previous = selectedID
        if !library.notes.contains(where: { $0.id == selectedID && $0.deleted == nil }) {
            library.selectedID = notes.first?.id
        }
        // A different note must reach the editor as a note switch, not as an
        // undoable edit of the previous note's text.
        if selectedID != previous { stopCapture(); focusToken = UUID() }
        draft = selected?.content ?? ""
    }

    func select(_ id: String) {
        guard ready, let note = library.notes.first(where: { $0.id == id }) else { return }
        stopCapture()
        pruneEmpty(except: id)
        library.selectedID = id; draft = note.content; focusToken = UUID()
        changed(); analyze()
    }

    private func pruneEmpty(except id: String? = nil) {
        library.notes.removeAll { $0.id != id && $0.slot == nil && $0.deleted == nil && !noteWindows.contains($0.id) && $0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func startNewNote(content: String = "") {
        guard ready else { return }
        stopCapture(); pruneEmpty()
        let note = ScratchNote(content: content)
        library.notes.insert(note, at: 0); library.selectedID = note.id
        draft = content; scope = "stack"; query = ""; focusToken = UUID()
        changed(); analyze()
    }

    func inlineEdited(_ text: String) {
        guard let selectedID else { return }
        edit(selectedID, text: text)
    }

    /// Edits any note, from the dock editor or a popped-out window; the other
    /// editor showing the same note picks the text up from the library.
    func edit(_ id: String, text: String) {
        guard ready, let index = library.notes.firstIndex(where: { $0.id == id && $0.deleted == nil }) else { return }
        guard text.utf8.count <= QuickNoteDatabase.contentLimit else { fail("Notes are limited to 2 MB."); return }
        library.notes[index].content = text; library.notes[index].modified = Date()
        if id == selectedID { draft = text }
        changed()
        if id == selectedID { analyze() }
        analyzePopped(id)
    }

    /// Opens a note (the selected one by default) in its own floating window.
    func popOut(_ id: String? = nil) {
        guard ready, let id = id ?? selectedID, library.notes.contains(where: { $0.id == id && $0.deleted == nil }) else { return }
        noteWindows.show(id: id, model: self)
        analyzePopped(id)
    }

    func poppedClosed(_ id: String) {
        poppedTasks.removeValue(forKey: id)?.cancel()
        poppedAnalyses[id] = nil
    }

    private func analyzePopped(_ id: String) {
        poppedTasks.removeValue(forKey: id)?.cancel()
        guard noteWindows.contains(id), let text = library.notes.first(where: { $0.id == id })?.content else { return }
        if let cached = presentations.result(for: id, text: text) { poppedAnalyses[id] = cached; return }
        let tools = tools
        poppedTasks[id] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
                let result = try await tools.analyze(text)
                guard let self, !Task.isCancelled, self.noteWindows.contains(id),
                      self.library.notes.contains(where: { $0.id == id && $0.content == text }) else { return }
                self.presentations.insert(result, for: id)
                self.poppedAnalyses[id] = result
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
        }
    }

    /// Slash commands typed in a popped-out note. Only those about that note
    /// apply; the rest act on the dock's selection, so they stay as text.
    func poppedCommand(_ line: String, id: String) -> Bool {
        switch line.trimmingCharacters(in: .whitespaces).lowercased() {
        case "/copy": copyNote(id); return true
        default: return false
        }
    }

    func poppedShortcut(_ shortcut: String, id: String) -> Bool {
        switch shortcut {
        case "bigger", "smaller": return perform(shortcut: shortcut)
        case "close": noteWindows.close(id); return true
        default: return false
        }
    }

    func navigate(_ direction: Int) {
        let stack = notes.filter { $0.slot == nil }
        guard let i = stack.firstIndex(where: { $0.id == selectedID }) else { if let first = stack.first { select(first.id) }; return }
        let next = i + direction
        if next < 0 { startNewNote() }
        else if next < stack.count { select(stack[next].id) }
    }

    func promote(_ id: String? = nil) {
        guard let index = library.notes.firstIndex(where: { $0.id == (id ?? selectedID) && $0.deleted == nil && $0.slot == nil }) else { return }
        let note = library.notes.remove(at: index); library.notes.insert(note, at: 0); changed()
    }

    func trash(_ id: String? = nil) {
        guard let index = library.notes.firstIndex(where: { $0.id == (id ?? selectedID) && $0.deleted == nil && $0.slot == nil }) else { return }
        stopCapture(); library.notes[index].deleted = Date()
        ensureSelection(); changed(); analyze(); notice("Moved to The Void. Restore it from the Void tab.")
    }

    func restore(_ id: String) {
        guard let index = library.notes.firstIndex(where: { $0.id == id }) else { return }
        library.notes[index].deleted = nil; library.notes[index].slot = nil
        scope = "stack"; select(id); notice("Restored.")
    }

    func setSlot(_ slot: Int?) {
        guard let index = library.notes.firstIndex(where: { $0.id == selectedID && $0.deleted == nil }) else { return }
        if let slot, library.notes.contains(where: { $0.slot == slot && $0.deleted == nil && $0.id != selectedID }) {
            fail("Slot \(slot) is occupied. Free it from that note’s slot menu first."); return
        }
        library.notes[index].slot = slot; changed()
    }

    func jumpSlot(_ slot: Int) {
        guard ready else { return }
        if let note = notes.first(where: { $0.slot == slot }) { select(note.id) }
        else { startNewNote(); setSlot(slot) }
        scope = "slots"
    }

    func settings(expiry: Int? = nil, fontSize: Double? = nil, lined: Bool? = nil, mathColor: MathResultColor? = nil) {
        guard ready else { return }
        if let expiry { library.expiryDays = expiry; library.expire(); ensureSelection(); analyze() }
        if let fontSize { library.fontSize = min(28, max(11, fontSize)) }
        if let lined { library.linedPaper = lined }
        if let mathColor { library.mathResultColor = mathColor }
        changed()
    }

    private func search() {
        searchTask?.cancel()
        guard ready, active else { return }
        let notes = library.notes, query = query, scope = scope, tools = tools
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
                let ids = try await tools.search(notes, query: query, scope: scope)
                guard !Task.isCancelled else { return }; let matching = await tools.matchingNotes(notes, ids: ids)
                guard !Task.isCancelled else { return }; self?.visible = matching
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
        }
    }

    private func analyze() {
        analysisTask?.cancel()
        preloadTask?.cancel(); preloadTask = nil
        guard active else { return }
        guard let id = selectedID else { analysis = ScratchAnalysis(); return }
        let text = draft, tools = tools
        if let cached = presentations.result(for: id, text: text) {
            analysis = cached
            warmPresentations()
            return
        }
        analysisTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
                let result = try await tools.analyze(text)
                guard let self, !Task.isCancelled, self.selectedID == id, self.draft == text else { return }
                self.presentations.insert(result, for: id)
                self.analysis = result
                self.warmPresentations()
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
        }
    }

    private func warmPresentations() {
        guard active, preloadTask == nil else { return }
        let snapshot = library.notes, tools = tools
        preloadTask = Task(priority: .utility) { [weak self] in
            defer { if !Task.isCancelled { self?.preloadTask = nil } }
            do {
                let notes = try await tools.warmCandidates(snapshot)
                for note in notes {
                    try Task.checkCancellation()
                    guard let self, self.active else { return }
                    if self.presentations.result(for: note.id, text: note.content) != nil { continue }
                    let result = try await tools.analyze(note.content)
                    try Task.checkCancellation()
                    guard self.library.notes.contains(where: { $0.id == note.id && $0.content == note.content }) else { continue }
                    self.presentations.insert(result, for: note.id)
                    await Task.yield()
                }
            } catch { /* Preloading is optional; foreground analysis reports errors. */ }
        }
    }

    func copyDraft() {
        guard let selectedID else { return }
        copyNote(selectedID)
    }
    /// Native result Copy already wrote the clipboard; AutoPaste must not feed
    /// that result back into this note as external capture.
    func didCopyResult(_ text: String) {
        ownCopy = text
        pasteboardChange = pasteboard.changeCount
    }
    func copyNote(_ id: String) {
        guard let text = library.notes.first(where: { $0.id == id })?.content else { return }
        ownCopy = text
        context?.copyText(text); pasteboardChange = pasteboard.changeCount; notice("Copied.")
    }
    private func entity() -> VehlaDockWidgetSharedContext? {
        guard let selected else { return nil }
        return VehlaDockWidgetSharedContext(id: selected.id, kind: .text, sourceID: "quicknote", title: selected.title, body: draft)
    }
    func sendToNotes() {
        guard let entity = entity(), context?.app?.perform(.addToNotes, with: entity) == true else {
            fail("This Vehla version cannot add notes through the app bridge. Use Copy or Export."); return
        }
        notice("Sent to Vehla Notes.")
    }

    func beginImport() {
        guard ready else { return }
        stopCapture()
        importPresented = true; importPreview = nil; importing = true; status = nil
        let installed = ["com.chabomakers.Antinote", "com.chabomakers.Antinote-setapp"].contains {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser, importer = importer
        importTask?.cancel()
        importTask = Task { [weak self] in
            do {
                let preview = try await importer.discover(home: home, installed: installed)
                guard !Task.isCancelled else { return }; self?.acceptPreview(preview)
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
            if !Task.isCancelled { self?.importing = false }
        }
    }

    func chooseImportFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = ["sqlite", "sqlite3", "db", "store", "md", "markdown"].compactMap { UTType(filenameExtension: $0) } + [.json, .plainText]
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            let urls = panel.urls, importer = self.importer
            self.importing = true; self.importPreview = nil
            self.importTask?.cancel()
            self.importTask = Task { [weak self] in
                do {
                    let preview = try await importer.files(urls)
                    guard !Task.isCancelled else { return }; self?.acceptPreview(preview)
                } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
                if !Task.isCancelled { self?.importing = false }
            }
        }
    }
    private func acceptPreview(_ preview: ImportPreview) {
        importPreview = preview
        importPresentKeys = library.importedKeys(among: preview.notes.map(\.importKey))
        importSelection = Set(preview.notes.filter { !isImported($0) }.map(\.id))
    }
    func isImported(_ note: ScratchNote) -> Bool { note.importKey.map(importPresentKeys.contains) ?? false }
    func selectAllImports() { importSelection = Set(importPreview?.notes.filter { !isImported($0) }.map(\.id) ?? []) }
    func cancelImport() { importTask?.cancel(); importing = false; importPresented = false; importPreview = nil }
    func confirmImport() {
        guard let preview = importPreview, ready else { return }
        let incoming = preview.notes.filter { importSelection.contains($0.id) }
        let importer = importer
        importing = true
        importTask = Task { [weak self] in
            do {
                while let self, !Task.isCancelled {
                    let snapshot = self.library
                    let (merged, count) = try await importer.merged(incoming, library: snapshot)
                    guard !Task.isCancelled else { return }
                    guard self.library.revision == snapshot.revision else { continue }
                    self.library = merged; self.changed()
                    self.importPresented = false; self.importPreview = nil; self.importing = false
                    self.notice("Imported \(count) notes. Existing imports were skipped.")
                    return
                }
            } catch is CancellationError {} catch { self?.importing = false; self?.fail(error.localizedDescription) }
        }
    }

    func recover() {
        guard let repository else { return }
        // A pending autosave would rotate the backup this is about to restore.
        debounceTask?.cancel(); stopCapture()
        let previous = saveTask
        loadTask = Task { [weak self] in
            await previous?.value
            do {
                let state = try await repository.recover()
                guard let self else { return }
                self.library = state; self.savedRevision = state.revision; self.ready = true
                self.focusToken = UUID()
                self.loading = false; self.ensureSelection(); self.search(); self.analyze(); self.notice("Recovered the previous save.")
            } catch { self?.fail(error.localizedDescription) }
            self?.loadTask = nil
        }
    }

    func export(backup: Bool = false, markdown: Bool = false) {
        guard ready, backup || selected != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [backup ? .json : markdown ? UTType(filenameExtension: "md") ?? .plainText : .plainText]
        panel.nameFieldStringValue = backup ? "Vehla Scratchpad.json" : "\(Self.fileName(selected?.title ?? "Note")).\(markdown ? "md" : "txt")"
        let snapshot = library, text = draft
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { [weak self] in
                do {
                    try await Task.detached(priority: .utility) {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        let data = try backup ? JSONEncoder().encode(snapshot) : Data(text.utf8)
                        try data.write(to: url, options: .atomic)
                    }.value
                    self?.notice("Exported \(url.lastPathComponent).")
                } catch { self?.fail(error.localizedDescription) }
            }
        }
    }

    /// Titles become file names; path separators and colons are not allowed there.
    nonisolated static func fileName(_ title: String) -> String {
        let cleaned = title.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
        let name = String(String(cleaned).prefix(60)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return name.isEmpty ? "Note" : name
    }

    func replaceAll() {
        guard !findText.isEmpty, selected?.deleted == nil else { return }
        let text = draft, find = findText, replacement = replacement, sensitive = caseSensitive
        let id = selectedID
        replaceTask?.cancel()
        replaceTask = Task { [weak self] in
            let updated = await Task.detached(priority: .utility) {
                text.replacingOccurrences(of: find, with: replacement, options: sensitive ? [] : [.caseInsensitive])
            }.value
            guard let self, !Task.isCancelled, self.selectedID == id, self.draft == text else { return }
            guard updated != text else { self.notice("No matches for “\(find)”."); return }
            self.inlineEdited(updated)
        }
    }

    func command(_ line: String) -> Bool {
        switch line.trimmingCharacters(in: .whitespaces).lowercased() {
        case "/new": startNewNote(); return true
        case "/search": sidebar = true; searchFocusRequest += 1; return true
        case "/import": beginImport(); return true
        case "/export": export(); return true
        case "/copy": copyDraft(); return true
        default: break
        }
        var line = line.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("/") { line.removeFirst() }
        let lower = line.lowercased()
        if lower == "paste" || (lower.hasPrefix("paste(") && lower.hasSuffix(")")) {
            if autoPaste { stopCapture() }
            else { pasteDelimiter = lower == "paste" ? "\n" : String(line.dropFirst(6).dropLast()); startCapture() }
            return true
        }
        if lower == "timer p" { toggleStopwatch(); return true }
        if lower == "timer s" || lower == "timer 0" { stopStopwatch(); return true }
        if lower == "timer r" { stopwatchStart = Date(); stopwatchElapsed = 0; stopwatchPaused = false; return true }
        if let timer = ScratchTimerCommand.parse(line) {
            if let duration = timer.duration {
                guard context?.app?.startTimer(label: timer.label, duration: duration, context: entity()) == true else {
                    fail("This Vehla version cannot start timers through the app bridge."); return true
                }
                notice("Started \(timer.label) in Vehla Timers.")
            } else { stopwatchStart = Date(); stopwatchElapsed = 0; stopwatchPaused = false }
            return true
        }
        return false
    }
    func toggleStopwatch() {
        if stopwatchPaused { stopwatchStart = Date(); stopwatchPaused = false }
        else if let start = stopwatchStart { stopwatchElapsed += Date().timeIntervalSince(start); stopwatchPaused = true; stopwatchStart = nil }
    }
    func stopStopwatch() { stopwatchStart = nil; stopwatchElapsed = 0; stopwatchPaused = false }

    /// Menu commands routed from the editor, because SwiftUI keyboard
    /// shortcuts do not reliably reach the host's nonactivating popup.
    func perform(shortcut: String) -> Bool {
        guard ready else { return false }
        switch shortcut {
        case "find": findPresented.toggle()
        case "export": export()
        case "promote": promote()
        case "void":
            guard let note = selected, note.slot == nil, note.deleted == nil else { return false }
            deletePresented = true
        case "popout": popOut()
        case "swap": scope = scope == "slots" ? "stack" : "slots"; sidebar = true
        case "bigger": settings(fontSize: library.fontSize + 1)
        case "smaller": settings(fontSize: library.fontSize - 1)
        default: return false
        }
        return true
    }
    func escape() -> Bool {
        if autoPaste { stopCapture(); return true }
        if findPresented { findPresented = false; return true }
        return false
    }

    private func startCapture() {
        guard ready, let note = selected, note.deleted == nil else { return }
        autoPaste = true; captureNoteID = selectedID
        pasteboardChange = pasteboard.changeCount
        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                guard let self, self.autoPaste else { return }
                self.captureClipboard()
            }
        }
        notice("AutoPaste is on. Text you copy anywhere is added to this note until you turn it off.")
    }
    func stopCapture() {
        captureTask?.cancel(); captureTask = nil; autoPaste = false; captureNoteID = nil
    }
    /// Pasteboard markers apps use for passwords and one-off contents
    /// (nspasteboard.org); AutoPaste never collects them.
    nonisolated static let privatePasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType",
    ]
    /// Reads the system pasteboard rather than Vehla's clipboard history: the
    /// history only records while Clipboard Management is on, and it
    /// reorders rather than re-adds a repeated copy.
    private func captureClipboard() {
        guard let id = captureNoteID, selectedID == id,
              library.notes.contains(where: { $0.id == id && $0.deleted == nil }) else { stopCapture(); return }
        let board = pasteboard
        guard board.changeCount != pasteboardChange else { return }
        pasteboardChange = board.changeCount
        if board.types?.contains(where: { Self.privatePasteboardTypes.contains($0.rawValue) }) == true { return }
        guard let text = board.string(forType: .string), !text.isEmpty else { return }
        if text == ownCopy { ownCopy = nil; return }
        append(text, delimiter: pasteDelimiter, to: id)
    }
    private func append(_ text: String, delimiter: String = "\n", to id: String? = nil) {
        guard !text.isEmpty, let id = id ?? selectedID, let current = library.notes.first(where: { $0.id == id })?.content else { return }
        edit(id, text: current + (current.isEmpty ? "" : delimiter) + text)
    }
    /// Adds an image's text to `target` (a popped-out note), or to the selected
    /// note while the dock editor is showing.
    func recognizeImage(_ data: Data, into target: String? = nil) {
        let id = target ?? selectedID, tools = tools
        ocrTask?.cancel(); notice("Recognizing text locally…")
        ocrTask = Task { [weak self] in
            do {
                let text = try await tools.ocr(data: data)
                guard let self, !Task.isCancelled, let id, target != nil || (self.active && self.selectedID == id) else { return }
                self.append(text, to: id); self.notice("Image text added.")
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
        }
    }
    func recognizeFile(_ url: URL, into target: String? = nil) {
        let id = target ?? selectedID, tools = tools
        ocrTask?.cancel(); notice("Recognizing text locally…")
        ocrTask = Task { [weak self] in
            do {
                let data = try await Task.detached(priority: .utility) {
                    let accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 20 * 1_024 * 1_024 else { throw ScratchError.message("Image exceeds 20 MiB.") }
                    return try Data(contentsOf: url)
                }.value
                try Task.checkCancellation()
                let text = try await tools.ocr(data: data)
                guard let self, !Task.isCancelled, let id, target != nil || (self.active && self.selectedID == id) else { return }
                self.append(text, to: id); self.notice("Image text added.")
            } catch is CancellationError {} catch { self?.fail(error.localizedDescription) }
        }
    }
    private func notice(_ text: String) { statusIsError = false; status = text }
    private func fail(_ text: String) { statusIsError = true; status = text }
}
