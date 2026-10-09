import AppKit
import Foundation
import SQLite3
import Testing
import VehlaDockWidgetSDK
@testable import QuickNoteDockWidget

@Suite struct ScratchpadTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    @Test func firstRunSeedsOnceAndSavesLatestRevision() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = ScratchRepository(root: root)
        var state = try await repo.load()
        #expect(state.notes.count == 7)
        let original = state
        state.notes[0].content = "Actual user note"; state.revision = 2
        try await repo.save(state)
        try await repo.save(original)
        let reopened = try await ScratchRepository(root: root).load()
        #expect(reopened.notes[0].content == "Actual user note")
        #expect(reopened.revision == 2)
    }
    @Test func renameMigratesEntireLibraryWithoutChangingOriginal() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let old = parent.appendingPathComponent("com.wiseman.vehla.antinote")
        let root = parent.appendingPathComponent("com.wiseman.vehla.quicknote")
        let previous = ScratchRepository(root: old)
        var state = try await previous.load()
        state.notes[0].content = "math: My budget\ncoffee = 4.5\ncoffee * 6 ="
        state.notes[0].slot = 3; state.notes[1].deleted = Date()
        state.fontSize = 22; state.linedPaper = true; state.expiryDays = 7
        state.importedKeys = ["antinote:kept"]; state.revision = 12
        try await previous.save(state)
        let before = try Data(contentsOf: old.appendingPathComponent("scratchpad.json"))
        let migrated = try await ScratchRepository(root: root, legacyRoot: ScratchRepository.legacyDirectory(for: root)).load()
        #expect(migrated == state)
        #expect(try Data(contentsOf: old.appendingPathComponent("scratchpad.json")) == before)
        #expect(try await ScratchRepository(root: root).load() == state)
        #expect(ScratchRepository.legacyDirectory(for: parent) == nil)
        var local = state; local.revision += 1; local.notes[0].content = "Edited in QuickNote"
        try await ScratchRepository(root: root).save(local)
        #expect(try await ScratchRepository(root: root, legacyRoot: old).load() == local)
    }
    @Test func renameMigratesValidPrimaryWithDamagedBackup() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let old = parent.appendingPathComponent("old"), root = parent.appendingPathComponent("new")
        let state = try await ScratchRepository(root: old).load()
        try Data("broken".utf8).write(to: old.appendingPathComponent("scratchpad.previous.json"))
        #expect(try await ScratchRepository(root: root, legacyRoot: old).load() == state)
    }
    @Test func renameKeepsCorruptLibraryRecoverableInsteadOfSeedingTutorials() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let old = parent.appendingPathComponent("old"), root = parent.appendingPathComponent("new")
        let previous = ScratchRepository(root: old)
        var state = try await previous.load(); let first = state
        state.revision += 1; try await previous.save(state)
        try Data("corrupt".utf8).write(to: old.appendingPathComponent("scratchpad.json"))
        let repository = ScratchRepository(root: root, legacyRoot: old)
        await #expect(throws: (any Error).self) { try await repository.load() }
        #expect(try await repository.recover().notes == first.notes)
    }
    @Test func corruptPrimaryDoesNotEraseBackup() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let repo = ScratchRepository(root: root)
        var state = try await repo.load(); let first = state
        state.revision += 1; state.notes[0].content = "Second save"
        try await repo.save(state)
        try Data("broken json".utf8).write(to: root.appendingPathComponent("scratchpad.json"))
        let reopened = ScratchRepository(root: root)
        await #expect(throws: (any Error).self) { try await reopened.load() }
        let recovered = try await reopened.recover()
        #expect(recovered.notes == first.notes)
        #expect(try await ScratchRepository(root: root).load().notes == first.notes)
    }
    @Test func importNeverOverwritesAndSlotsDoNotCollide() throws {
        var state = ScratchLibrary(notes: [ScratchNote(content: "Local permanent", slot: 1)])
        let source = [ScratchNote(content: "Imported", slot: 1, importKey: "antinote:one"), ScratchNote(content: "Permanent", slot: 2, importKey: "antinote:two")]
        #expect(ScratchImporter.merge(source, into: &state) == 2)
        #expect(state.notes[1].slot == nil)
        #expect(state.notes[2].slot == 2)
        state.notes[1].content = "Edited locally"; state.notes[1].deleted = Date()
        #expect(ScratchImporter.merge(source, into: &state) == 0)
        #expect(state.notes[1].content == "Edited locally")
        try state.validate()
    }
    @Test func missingQuickNoteIsUsefulAndTextImportsDeduplicate() async throws {
        let home = try scratch(); defer { try? FileManager.default.removeItem(at: home) }
        let importer = ScratchImporter()
        let absent = try await importer.discover(home: home, installed: false)
        #expect(absent.notes.isEmpty)
        #expect(absent.message.contains("not installed"))
        let installed = try await importer.discover(home: home, installed: true)
        #expect(installed.message.contains("is installed"))
        let url = home.appendingPathComponent("Note.md")
        try Data("# Imported\nBody".utf8).write(to: url)
        let preview = try await importer.files([url, url])
        var state = ScratchLibrary()
        #expect(ScratchImporter.merge(preview.notes, into: &state) == 1)
    }
    @Test func expiryProtectsSlotsAndTrashIsRecoverable() throws {
        let now = Date(), old = now.addingTimeInterval(-10 * 86_400)
        var state = ScratchLibrary(notes: [ScratchNote(content: "Temporary", modified: old), ScratchNote(content: "Permanent", modified: old, slot: 1)], expiryDays: 7)
        state.expire(now: now)
        #expect(state.notes[0].deleted == now)
        #expect(state.notes[0].content == "Temporary")
        #expect(state.notes[1].deleted == nil)
    }
    @Test func presentationCacheBoundsMemoryAndRejectsChangedContent() {
        var cache = ScratchPresentationStore()
        for index in 0..<140 {
            cache.insert(ScratchAnalysis(source: "note", prepared: true, cacheCost: 1), for: "\(index)")
        }
        #expect(cache.count == ScratchPresentationStore.noteLimit)
        #expect(cache.result(for: "0", text: "note") == nil)
        #expect(cache.result(for: "139", text: "edited") == nil)
        #expect(cache.result(for: "139", text: "note") != nil)
        cache.insert(ScratchAnalysis(source: "large", prepared: true, cacheCost: ScratchPresentationStore.byteLimit), for: "large")
        #expect(cache.count == 1)
        #expect(cache.cost == ScratchPresentationStore.byteLimit)
        cache.insert(ScratchAnalysis(source: "too big", prepared: true, cacheCost: ScratchPresentationStore.byteLimit + 1), for: "large")
        #expect(cache.count == 0)
        #expect(cache.cost == 0)
    }
    @Test func calculationsVariablesUnitsAndInvalidExpressions() async throws {
        var parser = MathParser("100 + 15%")
        #expect(try parser.evaluate() == 115)
        parser = MathParser("50% of 200")
        #expect(try parser.evaluate() == 100)
        parser = MathParser("2^3^2")
        #expect(try parser.evaluate() == 512)
        parser = MathParser("sqrt(16) + 2 * 3")
        #expect(try parser.evaluate() == 10)
        parser = MathParser("1 / 0")
        #expect(throws: (any Error).self) { try parser.evaluate() }
        parser = MathParser("someFunction(123)")
        #expect(throws: (any Error).self) { try parser.evaluate() }
        let tools = ScratchTools()
        let result = try await tools.analyze("math\ncoffee = 4.5\npeople = 6\ncoffee * people =\n10 km to mi =")
        #expect(result.results[2].contains("27"))
        #expect(result.results[3].contains("6.213712 mi"))
        #expect(result.mathResults[2].answer == "27")
        #expect((result.source as NSString).substring(with: result.mathResults[2].range) == "coffee * people =")
        let unicode = try await tools.analyze("math: ☕️\r\nprice = 4\r\nprice * 2 =")
        #expect((unicode.source as NSString).substring(with: unicode.mathResults.last!.range) == "price * 2 =")
        let sum = try await tools.analyze("sum\nTrain 28\nLunch 16.50\n// ignore 100")
        #expect(sum.results.first?.contains("44.5") == true)
    }
    @Test func searchScopesDoNotLeakTrashOrSlots() async throws {
        let notes = [ScratchNote(content: "Apple"), ScratchNote(content: "Apple", slot: 1), ScratchNote(content: "Apple", deleted: Date())]
        let tools = ScratchTools()
        #expect(try await tools.search(notes, query: "APPLE", scope: "stack") == [notes[0].id])
        #expect(try await tools.search(notes, query: "apple", scope: "slots") == [notes[1].id])
        #expect(try await tools.search(notes, query: "apple", scope: "void") == [notes[2].id])
    }
    @Test func timersParseWithoutAmbiguousLabelColons() {
        #expect(ScratchTimerCommand.parse("timer")?.duration == nil)
        #expect(ScratchTimerCommand.parse("timer 3:30")?.duration == 210)
        #expect(ScratchTimerCommand.parse("timer 5: Tea: then laundry")?.label == "Tea: then laundry")
        #expect(ScratchTimerCommand.parse("timer 5: Tea")?.duration == 300)
        #expect(ScratchTimerCommand.parse("timer invalid") == nil)
    }
    @Test func modernImportReadsAllRowsAndHonorsSlottedFlag() async throws {
        let root = try scratch(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("notes.sqlite3")
        var handle: OpaquePointer?
        #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
        let database = try #require(handle)
        defer { sqlite3_close(database) }
        let sql = """
        CREATE TABLE notes (id TEXT PRIMARY KEY, content TEXT, slotIndex INTEGER, isSlotted INTEGER, softDeleted INTEGER);
        WITH RECURSIVE counter(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM counter WHERE x < 1500)
        INSERT INTO notes SELECT 'note-' || x, 'Text ' || x, 0, 0, 0 FROM counter;
        INSERT INTO notes VALUES ('permanent', 'Keep this', 2, 1, 0);
        INSERT INTO notes VALUES ('deleted', 'Hidden', 0, 0, 1);
        """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        let before = try Data(contentsOf: url)
        let preview = try await ScratchImporter().database(url)
        #expect(preview.notes.count == 1501)
        #expect(preview.notes.first(where: { $0.content == "Text 1" })?.slot == nil)
        #expect(preview.notes.first(where: { $0.content == "Keep this" })?.slot == 3)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func invalidLibraryRejectsDuplicateIDsAndOversizedText() {
        var library = ScratchLibrary(notes: [ScratchNote(id: "a", content: "1"), ScratchNote(id: "a", content: "2")])
        #expect(throws: (any Error).self) { try library.validate() }
        library.notes = [ScratchNote(content: String(repeating: "a", count: 2_000_001))]
        #expect(throws: (any Error).self) { try library.validate() }
    }
}

@Suite(.serialized) @MainActor struct ScratchpadIntegrationTests {
    private func waitReady(_ model: QuickNoteModel) async throws {
        for _ in 0..<100 {
            if model.ready { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw ScratchError.message("Model failed to load: \(model.status ?? "unknown")")
    }
    @Test func hostBridgesAndCloseFlush() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let theme = VehlaDockWidgetTheme(isDark: false, accentColor: .systemBlue, primaryTextColor: .labelColor,
                                        secondaryTextColor: .secondaryLabelColor, surfaceColor: .windowBackgroundColor)
        var actions: [VehlaDockWidgetAction] = []
        var published: VehlaDockWidgetSharedContext?
        var timerDuration: TimeInterval?
        let app = VehlaDockWidgetAppBridge(currentContextHandler: { nil }, publishHandler: { published = $0; return true },
                                          actionHandler: { _, _ in true }, timerHandler: { _, duration, _ in timerDuration = duration; return true })
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "quicknote", dataDirectory: root, theme: theme,
                                             app: app, invalidationHandler: {}, actionHandler: { actions.append($0) })
        let model = QuickNoteModel(); model.configure(context)
        try await waitReady(model)
        model.startNewNote(); model.inlineEdited("Saved on immediate close")
        let id = model.selectedID
        model.select(try #require(id))
        #expect(published == nil)
        #expect(actions.isEmpty)
        model.copyDraft(); #expect(actions.count == 1)
        #expect(model.command("timer 3:30: Tea"))
        #expect(timerDuration == 210)
        _ = model.command("paste"); #expect(model.autoPaste)
        model.close(); #expect(!model.autoPaste); #expect(model.context == nil)
        for _ in 0..<100 {
            if let reopened = try? await ScratchRepository(root: root).load(), reopened.notes.first(where: { $0.id == id })?.content == "Saved on immediate close" { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Closing did not flush the accepted edit")
    }
    @Test func listHeaderAndNonItemsNeverReceiveCheckboxes() {
        let text = "list: Shopping\nMilk\n// comment\n# Heading\n1. numbered\n- bullet\n[] Bread\n"
        let boxes = NoteCheckbox.find(in: text)
        #expect(boxes.count == 2)
        #expect(boxes[0].implicit)
        #expect((text as NSString).substring(with: boxes[0].body) == "Milk")
        #expect(!boxes[1].implicit)
        #expect(boxes.allSatisfy { $0.marker.location > 0 })
        let view = InlineTextView(usingTextLayoutManager: false)
        view.string = "list: Shopping"
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "list: Shopping\n")
        view.detach()
    }

    @Test func nativeCommandShortcutsRouteThroughTheWidget() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        var commands: [String] = []
        view.onCommand = { commands.append($0); return true }
        for key in ["n", "f"] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: 0))
            #expect(view.performKeyEquivalent(with: event))
        }
        #expect(commands == ["/new", "/search"])
        view.detach()
    }
    @Test func slashCommandsAndCheckTriggerUseNativeEdits() {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.allowsUndo = true
        view.string = "/ma"; view.setSelectedRange(NSRange(location: 3, length: 0))
        var index = 0
        #expect(view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: &index) == ["/math"])
        view.string = "/list"; view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "[] ")
        view.insertText("Milk/", replacementRange: view.selectedRange())
        view.insertText("x", replacementRange: view.selectedRange())
        #expect(view.string == "[x] Milk")
        view.insertText("/", replacementRange: view.selectedRange())
        view.insertText("x", replacementRange: view.selectedRange())
        #expect(view.string == "[] Milk")
        view.string = "list: Budget\n/math"
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0)); view.insertNewline(nil)
        #expect(view.string == "list: Budget\nmath\n", "A slash mode starts a section; it never rewrites the note header")
        view.string = "/unknown"; view.setSelectedRange(NSRange(location: 8, length: 0)); view.insertNewline(nil)
        #expect(view.string == "/unknown\n")
        view.detach()
    }

    @Test func checkboxPositionsStayVisibleWhileTyping() async throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.string = "list: Shopping\n[] Milk\n[] Bread"
        view.restyle(); try await Task.sleep(for: .milliseconds(150))
        let old = view.checkboxes
        #expect(old.count == 2)
        let position = (view.string as NSString).range(of: "Milk").location + 4
        view.insertText("!", replacementRange: NSRange(location: position, length: 0))
        view.restyle()
        #expect(view.checkboxes.count == 2)
        #expect(view.checkboxes[0].marker == old[0].marker)
        #expect(view.checkboxes[1].marker.location == old[1].marker.location + 1)
        view.detach()
    }

    @Test func nativeEditorContinuesListsAndHasUndo() {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.allowsUndo = true
        view.string = "list: Today\nBuy milk"
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "list: Today\nBuy milk\n")
        view.string = "- [x] Done"; view.setSelectedRange(NSRange(location: 10, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "- [x] Done\n- [ ] ")
        view.detach()
    }
    @Test func headingStylingDoesNotTurnBodyTextBold() async throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.string = "# Heading\nPlain body"
        view.restyle()
        try await Task.sleep(for: .milliseconds(180))
        view.restyle()
        try await Task.sleep(for: .milliseconds(180))
        let font = try #require(view.textStorage?.attribute(.font, at: 12, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 15)
        #expect(!NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        view.detach()
    }

    @Test func twoFingerNavigationCommitsOnceAndIgnoresMomentum() {
        var tracker = NoteSwipeTracker()
        #expect(tracker.step(x: 0, y: 0, phase: .began) == .passThrough)
        #expect(tracker.step(x: 70, y: 2, phase: .changed) == .consume)
        #expect(tracker.step(x: 70, y: 1, phase: .changed) == .consume)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) == .navigate(-1))
        #expect(tracker.step(x: 100, y: 0, phase: [], momentum: .began) == .consume)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) != .navigate(-1))
        _ = tracker.step(x: 0, y: 0, phase: .began)
        _ = tracker.step(x: -140, y: 0, phase: .changed)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) == .navigate(1))
    }

    @Test func navigationRequiresDeliberateHorizontalTravel() {
        for distance in [60.0, 75.0, 110.0] {
            var tracker = NoteSwipeTracker()
            _ = tracker.step(x: 0, y: 0, phase: .began)
            _ = tracker.step(x: distance, y: 0, phase: .changed)
            #expect(tracker.step(x: 0, y: 0, phase: .ended) == .consume)
        }
        var diagonal = NoteSwipeTracker()
        _ = diagonal.step(x: 0, y: 0, phase: .began)
        #expect(diagonal.step(x: 18, y: 10, phase: .changed) == .passThrough)
        _ = diagonal.step(x: 150, y: 0, phase: .changed)
        #expect(diagonal.step(x: 0, y: 0, phase: .ended) == .passThrough)
    }

    @Test func unchangedNotesRestoreMathAndFormattingImmediately() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let math = ScratchNote(content: "math\ncoffee = 4.5\ncoffee * 6 =")
        let list = ScratchNote(content: "list: Shopping\nMilk\n[x] Bread\n**Remember**")
        try await ScratchRepository(root: root).save(ScratchLibrary(notes: [math, list], selectedID: math.id))
        let theme = VehlaDockWidgetTheme(isDark: false, accentColor: .systemBlue, primaryTextColor: .labelColor,
            secondaryTextColor: .secondaryLabelColor, surfaceColor: .windowBackgroundColor)
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "quicknote", dataDirectory: root,
            theme: theme, invalidationHandler: {}, actionHandler: { _ in })
        let model = QuickNoteModel(); model.configure(context)
        try await waitReady(model)
        #expect(model.analysis.prepared)
        #expect(model.analysis.source == math.content)
        // Wait for background warming once, then require synchronous restoration.
        try await Task.sleep(for: .milliseconds(350))
        model.select(list.id)
        #expect(model.analysis.source == list.content)
        let editor = InlineTextView(usingTextLayoutManager: false)
        editor.string = list.content
        #expect(editor.restorePresentation(model.analysis))
        #expect(editor.checkboxes.count == 3)
        let boldRange = (editor.string as NSString).range(of: "Remember")
        let font = try #require(editor.textStorage?.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        model.select(math.id)
        #expect(model.analysis.source == math.content)
        #expect(model.analysis.mathResults.map(\.answer) == ["4.5", "27"])
        model.stop(); model.start()
        #expect(model.analysis.mathResults.map(\.answer) == ["4.5", "27"])
        model.inlineEdited("math\ncoffee = 10\ncoffee * 6 =")
        model.select(list.id)
        #expect(model.analysis.source == list.content)
        try await Task.sleep(for: .milliseconds(350))
        model.select(math.id)
        #expect(model.analysis.mathResults.map(\.answer) == ["10", "60"])
        editor.detach(); model.close()
    }

    @Test func verticalShortCancelledAndMouseGesturesDoNotNavigate() {
        var tracker = NoteSwipeTracker()
        _ = tracker.step(x: 0, y: 0, phase: .began)
        #expect(tracker.step(x: 1, y: 20, phase: .changed) == .passThrough)
        #expect(tracker.step(x: 100, y: 1, phase: .changed) == .passThrough)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) == .passThrough)
        _ = tracker.step(x: 0, y: 0, phase: .began)
        _ = tracker.step(x: 20, y: 0, phase: .changed)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) == .consume)
        _ = tracker.step(x: 0, y: 0, phase: .began)
        _ = tracker.step(x: 100, y: 0, phase: .changed)
        #expect(tracker.step(x: 0, y: 0, phase: .cancelled) == .consume)
        #expect(tracker.step(x: 0, y: 0, phase: .ended) == .passThrough)
        #expect(tracker.step(x: 100, y: 0, phase: [], precise: false) == .passThrough)
    }

    @Test func inlineMathKeepsAnswersDuringEdits() async throws {
        let editor = InlineTextView(usingTextLayoutManager: false)
        editor.string = "math\ncoffee = 4.5\npeople = 6\ncoffee * people ="
        let tools = ScratchTools()
        editor.mathAnalysis = try await tools.analyze(editor.string)
        let location = (editor.string as NSString).range(of: "4.5").location
        editor.insertText("1", replacementRange: NSRange(location: location, length: 0))
        #expect(editor.mathAnalysis.mathResults.map(\.answer) == ["4.5", "6", "27"])
        #expect((editor.string as NSString).substring(with: editor.mathAnalysis.mathResults[2].range) == "coffee * people =")
        editor.mathAnalysis = try await tools.analyze(editor.string)
        #expect(editor.mathAnalysis.mathResults.map(\.answer) == ["14.5", "6", "87"])
        editor.detach()
    }

    @Test func pluginSurfacesRenderAndShareSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = NSApplication.shared
        let theme = VehlaDockWidgetTheme(isDark: false, accentColor: .systemIndigo, primaryTextColor: .labelColor,
                                        secondaryTextColor: .secondaryLabelColor, surfaceColor: .windowBackgroundColor)
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "quicknote", dataDirectory: root, theme: theme,
                                             invalidationHandler: {}, actionHandler: { _ in })
        let plugin = QuickNoteDockWidgetPlugin()
        #expect(plugin.apiVersion == VehlaDockWidgetAPIVersion)
        let popup = try plugin.makeViewController(widgetID: "quicknote", surface: .popup, context: context)
        _ = try plugin.makeViewController(widgetID: "quicknote", surface: .compact, context: context)
        _ = try plugin.makeViewController(widgetID: "quicknote", surface: .inline, context: context)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentViewController = popup
        popup.view.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        try await Task.sleep(for: .milliseconds(450))
        window.setContentSize(NSSize(width: 760, height: 680))
        popup.view.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        popup.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        popup.view.layoutSubtreeIfNeeded()
        #expect(popup.view.bounds.width == 760)
        #expect(popup.view.subviews.count == 1)
        #expect(popup.view.subviews[0].bounds.width == 760)
        #expect(popup.view.subviews[0].bounds.height == 680)
        #expect(!popup.view.subviews[0].isOpaque)
        func findEditor(_ view: NSView) -> InlineTextView? {
            if let editor = view as? InlineTextView { return editor }
            return view.subviews.lazy.compactMap { findEditor($0) }.first
        }
        let editor = try #require(findEditor(popup.view))
        #expect(editor.enclosingScrollView is NoteScrollView)
        #expect(editor.enclosingScrollView!.bounds.height > 300)
        #expect(editor.enclosingScrollView!.bounds.width > 500)
        #expect(editor.string.contains("A little room to think"))
        if let bitmap = popup.view.bitmapImageRepForCachingDisplay(in: popup.view.bounds) {
            popup.view.cacheDisplay(in: popup.view.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 0)
            let paperColor = try #require(bitmap.colorAt(x: Int(380 * CGFloat(bitmap.pixelsWide) / popup.view.bounds.width),
                                                        y: Int(500 * CGFloat(bitmap.pixelsHigh) / popup.view.bounds.height)))
            #expect(paperColor.alphaComponent < 0.01)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: "/tmp/vehla-antinote-preview.png"))
            }
        } else { Issue.record("Popup could not render") }
        let mathText = "math: Budget\ncoffee = 4.50\npeople = 6\ncoffee * people =\n(120 + 35) / 2 =\n100 + 15% =\n10 km to mi ="
        editor.string = mathText
        editor.mathAnalysis = try await ScratchTools().analyze(mathText)
        editor.restyle()
        try await Task.sleep(for: .milliseconds(150))
        #expect(editor.string == mathText)
        #expect(editor.textContainer!.widthTracksTextView, "Math must not narrow the whole note")
        let style = editor.textStorage!.attribute(.paragraphStyle, at: (mathText as NSString).range(of: "coffee * people").location, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.tailIndent == -InlineTextView.answerWidth, "Math lines reserve room for their answers")
        if let bitmap = popup.view.bitmapImageRepForCachingDisplay(in: popup.view.bounds) {
            popup.view.cacheDisplay(in: popup.view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: "/tmp/vehla-antinote-inline-math.png"))
            }
        }
        plugin.widget("quicknote", didEnter: .hidden)
        plugin.widgetWillClose("quicknote")
        window.contentViewController = nil
    }
}
