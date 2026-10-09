import AppKit
import Testing
@testable import QuickNoteDockWidget

struct LinedPaperTests {
    @Test @MainActor func proseInMathNotesUsesFullPaperWidth() async throws {
        _ = NSApplication.shared
        let editor = InlineTextView(usingTextLayoutManager: false)
        defer { editor.detach() }
        editor.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        editor.textContainer?.containerSize = NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        editor.baseFont = .systemFont(ofSize: 24)
        let prose = String(repeating: "abcdefghij", count: 12)
        editor.string = "math\n25/2 =\n" + prose
        editor.mathAnalysis = try await ScratchTools().analyze(editor.string)
        editor.restyle()
        let storage = try #require(editor.textStorage)
        let proseStart = (editor.string as NSString).range(of: prose).location
        let proseStyle = storage.attribute(.paragraphStyle, at: proseStart, effectiveRange: nil) as? NSParagraphStyle
        #expect((proseStyle?.tailIndent ?? 0) == 0)
        let mathStyle = storage.attribute(.paragraphStyle, at: 5, effectiveRange: nil) as? NSParagraphStyle
        #expect(mathStyle?.tailIndent == -InlineTextView.answerWidth)
        let manager = try #require(editor.layoutManager)
        let container = try #require(editor.textContainer)
        manager.ensureLayout(for: container)
        let glyph = manager.glyphIndexForCharacter(at: proseStart)
        let used = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
        #expect(used.maxX > 600)
        // Cached note presentation must preserve the same full-width wrapping.
        #expect(editor.restorePresentation(editor.mathAnalysis))
        let restored = storage.attribute(.paragraphStyle, at: proseStart, effectiveRange: nil) as? NSParagraphStyle
        #expect((restored?.tailIndent ?? 0) == 0)
    }

    @Test @MainActor func rulesFollowFontSizesWrappingAndBlankLines() async throws {
        _ = NSApplication.shared
        let editor = InlineTextView(usingTextLayoutManager: false)
        editor.string = "math: Paper\n25/2 =\nx = 7*9\ny = 0.6057*x - 31.555\n\nA long sentence that wraps as the editor becomes narrower and must stay on its own paper rows.\n"
        let source = editor.string
        editor.mathAnalysis = try await ScratchTools().analyze(source)
        editor.linedPaper = true
        defer { editor.detach() }
        for size in [11.0, 15.0, 24.0, 28.0] {
            for width in [350.0, 700.0] {
                editor.frame = NSRect(x: 0, y: 0, width: width, height: 600)
                editor.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
                editor.baseFont = .systemFont(ofSize: size)
                editor.restyle()
                let manager = try #require(editor.layoutManager)
                let container = try #require(editor.textContainer)
                manager.ensureLayout(for: container)
                let positions = editor.paperRulePositions(in: editor.bounds)
                #expect(positions.count > 5)
                #expect(positions == positions.sorted())
                #expect(Set(positions).count == positions.count)
                manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { fragment, used, _, _, _ in
                    let bottom = fragment.maxY + editor.textContainerOrigin.y
                    if bottom <= editor.bounds.maxY {
                        #expect(positions.contains { abs($0 - bottom) < 0.01 })
                        // Text must remain inside its row, including wrapped lines.
                        #expect(used.midY >= fragment.minY && used.midY <= fragment.maxY)
                    }
                }
                let scrolled = editor.paperRulePositions(in: NSRect(x: 0, y: 80, width: width, height: 160))
                #expect(scrolled.allSatisfy { $0 >= 80 && $0 <= 240 })
                #expect(editor.string == source)
            }
        }
    }
}
