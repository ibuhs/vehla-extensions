import AppKit
import SwiftUI
import Testing
import VehlaDockWidgetSDK
@testable import QuickNoteDockWidget

struct ResultInteractionTests {
    @Test @MainActor func noticesExpireButErrorsAndNewerMessagesRemain() async throws {
        let model = QuickNoteModel()
        model.statusDismissDelay = .milliseconds(100)
        defer { model.close() }
        model.status = "Copied."
        try await Task.sleep(for: .milliseconds(60))
        model.status = "Exported."
        try await Task.sleep(for: .milliseconds(60))
        #expect(model.status == "Exported.")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.status == nil)
        model.status = "Copied."
        model.sendToNotes() // Unsupported bridge reports an error.
        try await Task.sleep(for: .milliseconds(160))
        #expect(model.statusIsError && model.status != nil)
        model.status = nil
        model.statusIsError = false
        model.status = "Copied."
        model.close()
        try await Task.sleep(for: .milliseconds(160))
        #expect(model.status == "Copied.") // No delayed callbacks after teardown.
    }

    @Test func resultColorIsBackwardCompatibleAndPersists() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var state = ScratchLibrary()
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(state)) as? [String: Any])
        json.removeValue(forKey: "mathResultColor")
        let old = try decoder.decode(ScratchLibrary.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.mathResultColor == nil)
        for color in MathResultColor.allCases {
            state.mathResultColor = color
            let restored = try decoder.decode(ScratchLibrary.self, from: encoder.encode(state))
            #expect(restored.mathResultColor == color)
            try restored.validate()
        }
    }

    @Test @MainActor func answersAreNativeSelectableTextAndStayStable() async throws {
        _ = NSApplication.shared
        let editor = InlineTextView(usingTextLayoutManager: false)
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 300)
        editor.textContainer?.containerSize = NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        editor.string = "math\n25/2 =\n0.6057*71-31.555 ="
        let source = editor.string
        editor.mathAnalysis = try await ScratchTools().analyze(source)
        editor.restyle()
        func render() throws {
            let bitmap = try #require(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
            editor.cacheDisplay(in: editor.bounds, to: bitmap)
        }
        try render()
        let fields = editor.answerViews.values.sorted { $0.frame.minY < $1.frame.minY }
        #expect(fields.map(\.string) == ["12.5", "11.4497"])
        let first = try #require(fields.first)
        #expect(first.isSelectable && !first.isEditable)
        first.setSelectedRange(NSRange(location: 0, length: first.string.utf16.count))
        let clipboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        clipboard.declareTypes([.string], owner: nil)
        defer { clipboard.releaseGlobally(); editor.detach() }
        #expect(first.writeSelection(to: clipboard, types: [.string]))
        #expect(clipboard.string(forType: .string) == "12.5")
        try render()
        #expect(editor.answerViews.values.contains { $0 === first })
        #expect(first.selectedRange().length == 4)
        editor.resultColor = .yellow
        try render()
        #expect(first.textColor == .systemYellow)
        #expect(editor.string == source)
        editor.mathAnalysis = ScratchAnalysis()
        #expect(editor.answerViews.isEmpty)
    }

    @Test @MainActor func scopeTabsFitTheSidebar() async throws {
        _ = NSApplication.shared
        let model = QuickNoteModel()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { model.close(); try? FileManager.default.removeItem(at: root) }
        var library = ScratchLibrary()
        library.notes = (0..<120).map { _ in ScratchNote(content: "Scratch") }
        library.notes += (1...9).map { ScratchNote(content: "Slot", slot: $0) }
        library.notes += (0..<30).map { _ in ScratchNote(content: "Deleted", deleted: Date()) }
        try await ScratchRepository(root: root).save(library)
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .clear)
        model.configure(VehlaDockWidgetContext(packageID: "test", widgetID: "quicknote", dataDirectory: root,
                                               theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        for _ in 0..<100 where !model.ready { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.ready)
        let tabs = NSHostingView(rootView: ScopeTabs(model: model, primary: .white, secondary: .gray))
        tabs.frame = NSRect(x: 0, y: 0, width: 202, height: 32)
        tabs.layoutSubtreeIfNeeded()
        #expect(tabs.fittingSize.width <= 202)
    }
}
