import AppKit
import Foundation
import Testing
import VehlaDockWidgetSDK
@testable import QuickNoteDockWidget

@Suite struct ScratchRegressionTests {
    @Test func modeKeywordIsSharedAndExact() async throws {
        #expect(ScratchMode.keyword(of: "Codename ideas\nfoo") == "")
        #expect(ScratchMode.keyword(of: "code: Script\n  indented") == "code")
        #expect(ScratchMode.keyword(of: "List : Groceries\nMilk") == "list")
        #expect(ScratchMode.keyword(of: "listing") == "")
        #expect(try await ScratchTools().analyze("Codename ideas").mode == "text")
        let boxes = NoteCheckbox.find(in: "List : Groceries\nMilk")
        #expect(boxes.count == 1 && boxes[0].implicit)
    }

    @Test func sumKeepsGroupedThousandsAndHyphenatedWords() async throws {
        #expect(ScratchTools.numbers(in: "Rent 1,200.50") == [1200.5])
        #expect(ScratchTools.numbers(in: "Item-2 refund -5") == [2, -5])
        let result = try await ScratchTools().analyze("sum: Month\nRent 1,200\nPhone 45")
        #expect(result.results == ["Sum: 1,245 · 2 values"])
    }

    @Test func timerWithEmptyLabelKeepsDefault() {
        #expect(ScratchTimerCommand.parse("timer 5: ")?.label == "Scratchpad")
        #expect(ScratchTimerCommand.parse("timer 5: Tea")?.label == "Tea")
    }

    @Test func importingOwnBackupDoesNotDuplicateNotes() {
        var library = ScratchLibrary(notes: [ScratchNote(content: "Mine"), ScratchNote(content: "Also mine")])
        let backup = library.notes.map { note in
            var copy = note; copy.importKey = "vehla:\(note.id)"; copy.id = UUID().uuidString; return copy
        } + [ScratchNote(content: "New elsewhere", importKey: "vehla:\(UUID().uuidString)")]
        #expect(library.importedKeys(among: backup.map(\.importKey)).count == 2)
        #expect(ScratchImporter.merge(backup, into: &library) == 1)
        #expect(library.notes.map(\.content) == ["Mine", "Also mine", "New elsewhere"])
    }

    @Test func exportFileNamesAreSafe() {
        #expect(QuickNoteModel.fileName("a/b: c") == "a-b- c")
        #expect(QuickNoteModel.fileName("..") == "Note")
    }

    @Test @MainActor func slashListStartsAChecklistItemOnItsLine() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.string = "# Ideas\nKeep this prose.\n/list"
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        #expect(view.string == "# Ideas\nKeep this prose.\n[] ")
        view.insertText("Milk", replacementRange: view.selectedRange())
        view.insertNewline(nil)
        view.insertText("Eggs", replacementRange: view.selectedRange())
        #expect(view.string == "# Ideas\nKeep this prose.\n[] Milk\n[] Eggs")
        #expect(NoteCheckbox.find(in: view.string).count == 2)
        view.detach()
    }

    @Test @MainActor func everySlashMenuCommandWorksWhenChosen() throws {
        var expected: [String: String] = [
            "/list": "Note\n[] ", "/checkbox": "Note\n[] ", "/bullet": "Note\n- ", "/numbered": "Note\n1. ",
            "/text": "Note\n\n", "/timer": "Note\n/timer ",
        ]
        for mode in ["math", "sum", "average", "count", "code"] { expected["/" + mode] = "Note\n\(mode)\n" }
        let actions = ["/new", "/search", "/copy", "/paste", "/import", "/export"]
        let view = InlineTextView(usingTextLayoutManager: false)
        var index = 0
        view.string = "/"; view.setSelectedRange(NSRange(location: 1, length: 0))
        let menu = try #require(view.completions(forPartialWordRange: view.rangeForUserCompletion, indexOfSelectedItem: &index))
        #expect(Set(menu) == Set(expected.keys).union(actions).union(["/date", "/time"]))
        for word in menu {
            var received: [String] = []
            view.onCommand = { received.append($0); return true }
            view.string = "Note\n/"; view.setSelectedRange(NSRange(location: 6, length: 0))
            view.insertCompletion(word, forPartialWordRange: NSRange(location: 5, length: 1),
                                  movement: NSTextMovement.return.rawValue, isFinal: true)
            if let text = expected[word] { #expect(view.string == text, "\(word)") }
            else if actions.contains(word) { #expect(received == [word] && view.string == "Note\n", "\(word)") }
            else { #expect(view.string.count > 6 && !view.string.contains(word), "\(word)") }
        }
        view.detach()
    }

    @Test @MainActor func slashMenuFiltersAsYouTypeAndRunsTheChoice() throws {
        #expect(SlashCommand.matching("/s").prefix(2).map(\.name) == ["/sum", "/search"])
        #expect(SlashCommand.matching("/").count == SlashCommand.all.count)
        #expect(SlashCommand.matching("/zzz").isEmpty)
        let view = InlineTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        var commands: [String] = []
        view.onCommand = { commands.append($0); return true }
        view.string = "Note\n"; view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertText("/", replacementRange: view.selectedRange())
        #expect(view.visibleSlashCommands.count == SlashCommand.all.count)
        view.insertText("s", replacementRange: view.selectedRange())
        view.insertText("u", replacementRange: view.selectedRange())
        #expect(view.visibleSlashCommands.first == "/sum")
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(view.string == "Note\nsum\n")
        #expect(view.visibleSlashCommands.isEmpty)

        view.insertText("/", replacementRange: view.selectedRange())
        view.insertText("s", replacementRange: view.selectedRange())
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        #expect(commands == ["/search"])

        view.insertText("/", replacementRange: view.selectedRange())
        #expect(view.dismissSlashMenu())
        #expect(view.visibleSlashCommands.isEmpty)
        view.insertText("l", replacementRange: view.selectedRange())
        #expect(view.visibleSlashCommands.isEmpty, "Escape keeps this slash's menu closed")
        view.detach()
    }

    @Test func outlineBlocksFollowParagraphsAndHeadings() {
        let blocks = NoteOutlineBlock.blocks(in: "# Plan\nIntro line\nmore\n\n[] Milk\n[] Eggs\n\n\n## Later")
        #expect(blocks.map(\.title) == ["Plan", "Intro line", "Milk", "Later"])
        #expect(blocks.map(\.heading) == [true, false, false, true])
        #expect(blocks[1].preview == "more" && blocks[2].preview == "Eggs")
        #expect(blocks[2].location == ("# Plan\nIntro line\nmore\n\n" as NSString).length)
    }

    @Test @MainActor func railShowsTicksOnlyForScrollableNotesAndJumps() async throws {
        let scroll = NoteScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let view = InlineTextView(usingTextLayoutManager: false)
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.frame = NSRect(x: 0, y: 0, width: 374, height: 200)
        scroll.documentView = view
        scroll.attachRail(to: view)
        #expect(scroll.contentView.frame.width == 400 - NoteScrollRail.width, "The rail's strip is always reserved")
        view.string = "Short"; scroll.rail.reload()
        #expect(scroll.rail.slots.isEmpty)
        view.string = (1...40).map { "Paragraph \($0)\nbody" }.joined(separator: "\n\n")
        view.sizeToFit(); scroll.rail.reload()
        #expect(scroll.rail.slots.count > 10)
        var jumped: CGFloat?
        scroll.rail.onJump = { y, _ in jumped = y }
        scroll.rail.jump(toSlot: scroll.rail.slots.count - 1)
        #expect((jumped ?? 0) > 200)
        let first = try #require(scroll.rail.scrubOffset(at: NSPoint(x: 10, y: -100)))
        let last = try #require(scroll.rail.scrubOffset(at: NSPoint(x: 10, y: 10_000)))
        let middle = try #require(scroll.rail.scrubOffset(at: NSPoint(x: 10, y: scroll.rail.bounds.midY)))
        #expect(first < middle && middle < last, "Scrubbing moves continuously and clamps at both ends")
        #expect(!scroll.rail.mouseDownCanMoveWindow)
        view.detach()
    }

    @Test @MainActor func typedCheckboxGetsItsSpace() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        for key in ["[", "]", "M", "i", "l", "k"] { view.insertText(key, replacementRange: view.selectedRange()) }
        #expect(view.string == "[] Milk")
        view.string = "- [ "; view.setSelectedRange(NSRange(location: 4, length: 0))
        view.insertText("]", replacementRange: view.selectedRange())
        #expect(view.string == "- [ ] ")
        view.string = "see [link"; view.setSelectedRange(NSRange(location: 9, length: 0))
        view.insertText("]", replacementRange: view.selectedRange())
        #expect(view.string == "see [link]")
        view.detach()
    }

    @Test @MainActor func keywordLineStartsAListSection() {
        let text = "Ideas\nlist\nMilk\nEggs\n\nAfter the list"
        let ns = text as NSString
        #expect(NoteCheckbox.find(in: text).map { ns.substring(with: $0.body) } == ["Milk", "Eggs"])
    }

    @Test func sectionsComputeLocallyAndShareVariables() async throws {
        let text = "Trip notes\nrate = 3\nmath\nrate = 2\nrate * 5 =\n\nNot math 4 * 4 =\nsum: Food\nLunch 12\nDinner 20\n\nTotal 99"
        let result = try await ScratchTools().analyze(text)
        #expect(result.mode == "text")
        #expect(result.inlineMath)
        #expect(result.mathResults.map(\.answer) == ["2", "10", "32 · 2 values"])
        #expect(result.results == ["Sum · Food: 32 · 2 values"])
        let code = ScratchTextSpan.parse("Notes\ncode\n  let x = 1\n\nprose").filter { $0.kind == "code" }
        #expect(code.count == 1)
    }

    @Test func emptySectionsExplainWhatToTypeNext() async throws {
        let text = "Plans\nsum\n"
        let hints = try await ScratchTools().analyze(text).mathResults
        #expect(hints.count == 1 && hints[0].isHint && hints[0].range == NSRange(location: 6, length: 3))
        #expect(hints[0].answer.contains("add numbers"))
        let filled = try await ScratchTools().analyze("Plans\nsum\nTrain 28\nLunch 2").mathResults
        #expect(filled.map(\.answer) == ["30 · 2 values"] && !filled[0].isHint)
        let math = try await ScratchTools().analyze("math\n").mathResults
        #expect(math.first?.answer.hasPrefix("type an expression") == true)
        #expect(try await ScratchTools().analyze("math\n2 + 2 =").mathResults.map(\.answer) == ["4"])
    }

    @Test @MainActor func headingLevelsHaveDistinctSizes() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.baseFont = .systemFont(ofSize: 15)
        view.string = "# One\n## Two\n### Three\n#### Four\nBody"
        view.restyle()
        let text = view.string as NSString
        func size(_ word: String) -> CGFloat {
            (view.textStorage!.attribute(.font, at: text.range(of: word).location, effectiveRange: nil) as! NSFont).pointSize
        }
        #expect(size("One") > size("Two") && size("Two") > size("Three") && size("Three") > size("Four") && size("Four") > size("Body"))
        let marker = view.textStorage!.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect((marker?.alphaComponent ?? 1) < 0.5, "The # marker is dimmed")
        view.detach()
    }

    @Test @MainActor func headingsAndNewCheckboxesAreStyledImmediately() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.baseFont = .systemFont(ofSize: 15)
        view.string = "Notes\nsum\n[] Milk"
        view.restyle()
        let storage = try #require(view.textStorage)
        let keywordFont = storage.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(keywordFont?.isFixedPitch == true && keywordFont!.pointSize < 15)
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.insertNewline(nil)
        view.restyle()
        #expect(view.checkboxes.count == 2, "The continued item has its box before any delay")
        view.detach()
    }

    @Test func returnAtTheEndOfAnItemKeepsItsCheckbox() throws {
        let text = "[] Milk\n[] Eggs"
        let box = try #require(NoteCheckbox.find(in: text).first)
        #expect(box.adjusted(for: NSRange(location: NSMaxRange(box.body), length: 0), replacement: "\n") == box)
    }
}

@Suite(.serialized) @MainActor struct ModelRegressionTests {
    private func readyModel() async throws -> (QuickNoteModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let theme = VehlaDockWidgetTheme(isDark: false, accentColor: .systemBlue, primaryTextColor: .labelColor,
                                        secondaryTextColor: .secondaryLabelColor, surfaceColor: .windowBackgroundColor)
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "quicknote", dataDirectory: root, theme: theme,
                                             invalidationHandler: {}, actionHandler: { _ in })
        let model = QuickNoteModel(); model.configure(context)
        for _ in 0..<100 where !model.ready { try await Task.sleep(for: .milliseconds(20)) }
        try #require(model.ready)
        return (model, root)
    }

    @Test func pageLabelFollowsTheStack() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        let count = model.notes.filter { $0.slot == nil }.count
        #expect(model.pageLabel == "1 / \(count)")
        model.navigate(1)
        #expect(model.pageLabel == "2 / \(count)")
        model.setSlot(4)
        #expect(model.pageLabel == "Slot 4")
    }

    @Test func stoppingAPausedStopwatchHidesIt() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        model.toggleStopwatch()
        #expect(!model.stopwatchPaused, "Pausing without a running stopwatch must do nothing")
        #expect(model.command("timer"))
        model.toggleStopwatch(); #expect(model.stopwatchPaused)
        #expect(model.command("timer s"))
        #expect(!model.stopwatchPaused && model.stopwatchStart == nil)
    }

    @Test func trashingSwitchesNotesInsteadOfEditingThem() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        let token = model.focusToken
        model.trash()
        #expect(model.focusToken != token)
        #expect(model.draft == model.selected?.content)
    }

    @Test func slashTimerKeepsLabelCaseAndSearchRequestsFocus() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        var received: [String] = []
        let view = InlineTextView(usingTextLayoutManager: false)
        view.onCommand = { received.append($0); return true }
        view.string = "/timer 5: Tea"; view.setSelectedRange(NSRange(location: 13, length: 0))
        view.insertNewline(nil)
        #expect(received == ["/timer 5: Tea"])
        view.detach()
        let request = model.searchFocusRequest
        #expect(model.command("/search"))
        #expect(model.sidebar && model.searchFocusRequest == request + 1)
    }

    @Test func poppedOutNotesEditIndependentlyOfTheSelection() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        model.startNewNote()
        let popped = try #require(model.selectedID)
        model.popOut()
        #expect(model.noteWindows.contains(popped))
        // An empty popped-out note survives the empty-note pruning a new note triggers.
        model.startNewNote()
        let selected = try #require(model.selectedID)
        #expect(selected != popped && model.library.notes.contains { $0.id == popped })
        model.edit(popped, text: "math\n2 + 3 =")
        #expect(model.library.notes.first { $0.id == popped }?.content == "math\n2 + 3 =")
        #expect(model.selectedID == selected && model.draft.isEmpty)
        for _ in 0..<100 where model.poppedAnalyses[popped]?.source != "math\n2 + 3 =" { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.poppedAnalyses[popped]?.mode == "math")
        // Editing the selected note keeps the dock draft in step.
        model.edit(selected, text: "hello"); #expect(model.draft == "hello")
        // Slash commands about the dock's selection stay text in a popped-out note.
        #expect(!model.poppedCommand("/new", id: popped))
        #expect(model.poppedShortcut("close", id: popped))
        #expect(!model.noteWindows.contains(popped) && model.poppedAnalyses[popped] == nil)
    }

    @Test func autoPasteKeepsCollectingWhileThePopupIsClosed() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        model.pasteboard = board
        board.clearContents(); board.setString("before", forType: .string)
        model.startNewNote()
        #expect(model.command("/paste") && model.autoPaste)
        // Copying in another app closes the popup; capture must survive it.
        model.stop()
        #expect(model.autoPaste)
        func copy(_ text: String, private: Bool = false) async throws {
            board.clearContents()
            if `private` { board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil) }
            board.setString(text, forType: .string)
            for _ in 0..<50 where !model.draft.hasSuffix(text) { try await Task.sleep(for: .milliseconds(20)) }
        }
        try await copy("first"); try await copy("secret", private: true); try await copy("second")
        #expect(model.draft == "first\nsecond", "Only copies made after /paste, never concealed ones")
        model.start()
        #expect(model.command("/paste") && !model.autoPaste)
    }

    @Test func trashingAPoppedOutNoteClosesItsWindow() async throws {
        let (model, root) = try await readyModel(); defer { model.close(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(model.notes.first { $0.slot == nil }?.id)
        model.select(id); model.popOut()
        #expect(model.noteWindows.contains(id))
        model.trash(id)
        for _ in 0..<50 where model.noteWindows.contains(id) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!model.noteWindows.contains(id))
    }

    @Test func editorRoutesMenuShortcuts() throws {
        let view = InlineTextView(usingTextLayoutManager: false)
        var shortcuts: [String] = [], commands: [String] = []
        view.onShortcut = { shortcuts.append($0); return true }
        view.onCommand = { commands.append($0); return true }
        func press(_ key: String, _ flags: NSEvent.ModifierFlags = .command, keyCode: UInt16 = 0) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: keyCode))
            #expect(view.performKeyEquivalent(with: event))
        }
        try press("F", [.command, .shift]); try press("f"); try press("s"); try press("d")
        try press("!", [.command, .shift], keyCode: 18)
        try press("O", [.command, .shift]); try press("w")
        #expect(shortcuts == ["find", "export", "void", "promote", "popout", "close"])
        #expect(commands == ["/search"])
        view.detach()
    }

    @Test func tabNestsListItemsFromTheLineStart() {
        let view = InlineTextView(usingTextLayoutManager: false)
        view.allowsUndo = true
        view.string = "- Milk"; view.setSelectedRange(NSRange(location: 6, length: 0))
        view.insertTab(nil)
        #expect(view.string == "    - Milk")
        #expect(view.selectedRange().location == 10)
        view.insertBacktab(nil)
        #expect(view.string == "- Milk")
        view.string = "Plain"; view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertTab(nil)
        #expect(view.string == "Plain    ")
        view.detach()
    }
}
