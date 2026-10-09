import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Editable note text inside the popup. Vehla's popup keeps itself as first
/// responder, so once clicked this view takes key events straight from
/// Vehla's event stream and draws its own caret when AppKit will not.
/// Antinote checkbox lines (`[]`, `[ ]`, `- [ ]`, `[x]`, `- [x]`) show a
/// clickable checkbox in place of the marker.
struct InlineNoteEditor: NSViewRepresentable {
    var text: String
    var textColor: NSColor
    var autoFocus: Bool
    var onEdit: (String) -> Void
    var onSave: () -> Void
    var fontSize: Double = 15
    var focusToken: UUID = UUID()
    var analysis = ScratchAnalysis()
    var resultColor: MathResultColor = .automatic
    var onResultCopy: (String) -> Void = { _ in }
    var linedPaper = false
    var onCommand: (String) -> Bool = { _ in false }
    var onShortcut: (String) -> Bool = { _ in false }
    var onNavigate: (Int) -> Void = { _ in }
    var onEscape: () -> Bool = { false }
    var onImage: (Data) -> Void = { _ in }
    var onImageFile: (URL) -> Void = { _ in }
    var onOpenURL: (URL) -> Void = { _ in }

    func makeCoordinator() -> InlineEditorCoordinator {
        InlineEditorCoordinator(onEdit: onEdit, onOpenURL: onOpenURL)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoteScrollView()
        scroll.onNavigate = onNavigate
        scroll.hasVerticalScroller = false // NoteScrollRail replaces it
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.contentView.drawsBackground = false
        scroll.contentView.backgroundColor = .clear
        scroll.borderType = .noBorder
        let textView = InlineTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude)
        textView.baseFont = .systemFont(ofSize: fontSize)
        textView.font = textView.baseFont
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        // macOS draws predicted words as grey ghost text after a space (e.g. a
        // stray "=" after a new checkbox); a scratchpad shows only what was typed.
        textView.inlinePredictionType = .no
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.insertionPointColor = .controlAccentColor
        textView.baseColor = textColor
        textView.resultColor = resultColor
        textView.onResultCopy = onResultCopy
        textView.linedPaper = linedPaper
        textView.string = text
        if analysis.source == textView.string { textView.mathAnalysis = analysis }
        if !textView.restorePresentation(analysis) { textView.restyle() }
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onCommand = onCommand
        textView.onShortcut = onShortcut
        textView.onNavigate = onNavigate
        textView.onEscape = onEscape
        textView.onImage = onImage
        textView.onImageFile = onImageFile
        textView.onOpenURL = onOpenURL
        textView.focusOnAttach = autoFocus
        textView.registerForDraggedTypes([.png, .tiff])
        scroll.documentView = textView
        scroll.attachRail(to: textView)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: InlineEditorCoordinator) {
        (scroll.documentView as? InlineTextView)?.detach()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll as? NoteScrollView)?.onNavigate = onNavigate
        context.coordinator.onEdit = onEdit
        context.coordinator.onOpenURL = onOpenURL
        guard let textView = scroll.documentView as? InlineTextView else { return }
        textView.onResultCopy = onResultCopy
        if textView.linedPaper != linedPaper { textView.linedPaper = linedPaper; textView.needsDisplay = true }
        if textView.resultColor != resultColor { textView.resultColor = resultColor; textView.needsDisplay = true }
        textView.onSave = onSave
        textView.onCommand = onCommand
        textView.onShortcut = onShortcut
        textView.onNavigate = onNavigate
        textView.onEscape = onEscape
        textView.onImage = onImage
        textView.onImageFile = onImageFile
        textView.onOpenURL = onOpenURL
        var changed = false
        if textView.baseFont.pointSize != CGFloat(fontSize) { textView.baseFont = .systemFont(ofSize: fontSize); changed = true }
        let selectionChanged = textView.focusToken != focusToken
        if selectionChanged {
            textView.focusToken = focusToken
            textView.mathAnalysis = ScratchAnalysis()
            textView.clearDerivedStyle()
            textView.undoManager?.removeAllActions()
            if autoFocus { textView.requestFocus() }
        }
        if textView.string != text {
            if selectionChanged { textView.string = text }
            else {
                // External capture/replace edits participate in native Undo.
                let delegate = textView.delegate
                textView.delegate = nil
                textView.insertText(text, replacementRange: NSRange(location: 0, length: (textView.string as NSString).length))
                textView.delegate = delegate
            }
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            changed = true
        }
        if textView.baseColor != textColor {
            (scroll as? NoteScrollView)?.rail.color = textColor
            textView.baseColor = textColor
            changed = true
        }
        if selectionChanged || changed {
            if !textView.restorePresentation(analysis) { textView.restyle() }
        }
        if analysis.source == textView.string && analysis != textView.mathAnalysis {
            textView.mathAnalysis = analysis
            _ = textView.restorePresentation(analysis)
        }
    }
}

@MainActor
final class InlineEditorCoordinator: NSObject, NSTextViewDelegate {
    var onEdit: (String) -> Void

    var onOpenURL: (URL) -> Void
    init(onEdit: @escaping (String) -> Void, onOpenURL: @escaping (URL) -> Void) {
        self.onEdit = onEdit; self.onOpenURL = onOpenURL
    }
    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let url = link as? URL { onOpenURL(url) }
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        (textView as? InlineTextView)?.restyle()
        onEdit(textView.string)
    }
}

struct NoteCheckbox: Equatable, Sendable {
    /// The whole marker, e.g. `- [ ]` or `[]`.
    var marker: NSRange
    /// Everything between the brackets (empty, a space, or `x`).
    var inner: NSRange
    var dashed: Bool
    var checked: Bool
    /// The rest of the line after the marker.
    var body: NSRange
    var implicit = false

    private static let pattern = try! NSRegularExpression(
        pattern: #"^[ \t]*((- )?\[([ xX]?)\])(?=[ \t]|$)(.*)$"#,
        options: [.anchorsMatchLines]
    )

    static func find(in text: String) -> [NoteCheckbox] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var boxes = pattern.matches(in: text, range: whole).map { match in
            let inner = match.range(at: 3)
            let mark = (text as NSString).substring(with: inner)
            return NoteCheckbox(
                marker: match.range(at: 1),
                inner: inner,
                dashed: match.range(at: 2).location != NSNotFound,
                checked: mark.lowercased() == "x",
                body: match.range(at: 4)
            )
        }
        let source = text as NSString
        let explicitLines = Set(boxes.map { source.lineRange(for: $0.marker).location })
        for section in ScratchMode.sections(in: text) where section.mode == "list" {
            for line in section.lines.map(\.range) {
                let content = source.substring(with: line)
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"), !trimmed.hasPrefix("/"),
                      trimmed.range(of: #"^(?:[-*]\s|\d+\.\s)"#, options: .regularExpression) == nil,
                      !explicitLines.contains(line.location) else { continue }
                let indent = content.prefix(while: { $0 == " " || $0 == "\t" }).utf16.count
                let start = line.location + indent
                boxes.append(NoteCheckbox(marker: NSRange(location: start, length: 0), inner: NSRange(location: start, length: 0),
                                          dashed: false, checked: false, body: NSRange(location: start, length: content.utf16.count - indent), implicit: true))
            }
        }
        return boxes.sorted { $0.marker.location < $1.marker.location }
    }

    /// The edit that flips this checkbox, keeping Antinote's marker style.
    var toggle: (range: NSRange, replacement: String) {
        if implicit { return (inner, "[x] ") }
        if checked {
            return (inner, dashed ? " " : "")
        }
        return (inner, "x")
    }

    func adjusted(for edit: NSRange, replacement: String) -> Self? {
        let delta = replacement.utf16.count - edit.length
        if implicit, edit.location == marker.location, edit.length == 0 {
            guard !replacement.contains(where: \.isNewline) else { return nil }
            var box = self; box.body.length += delta; return box
        }
        if NSMaxRange(edit) <= marker.location {
            var box = self
            box.marker.location += delta; box.inner.location += delta; box.body.location += delta
            return box
        }
        if edit.location < NSMaxRange(marker) { return nil }
        // Return at the end of an item starts the next line; this box is unchanged.
        if edit.location == NSMaxRange(body), edit.length == 0, replacement.first?.isNewline == true { return self }
        if edit.location <= NSMaxRange(body) {
            guard NSMaxRange(edit) <= NSMaxRange(body), !replacement.contains(where: \.isNewline) else { return nil }
            var box = self
            box.body.length = max(0, body.length + delta)
            if implicit && box.body.length == 0 { return nil }
            return box
        }
        return self
    }
}

final class InlineTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCommand: (String) -> Bool = { _ in false }
    var onShortcut: (String) -> Bool = { _ in false }
    var onNavigate: (Int) -> Void = { _ in }
    var onEscape: () -> Bool = { false }
    var onImage: (Data) -> Void = { _ in }
    var onImageFile: (URL) -> Void = { _ in }
    var onOpenURL: (URL) -> Void = { _ in }
    var focusToken: UUID?
    private var spans: [ScratchTextSpan] = []
    private var styleTask: Task<Void, Never>?
    func detach() {
        armed = false; removeMonitor(); styleTask?.cancel(); hideSlashMenu()
        for answer in answerViews.values { answer.detach() }
    }
    private var slashMenu: SlashMenuView?
    /// The `/` whose menu was dismissed with Escape; it stays closed until a new one is typed.
    private var dismissedSlash: Int?
    var visibleSlashCommands: [String] { slashMenu.map { $0.isHidden ? [] : $0.items.map(\.name) } ?? [] }
    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }; self.arm()
        }
    }
    var focusOnAttach = false
    var baseFont: NSFont = .systemFont(ofSize: 15)
    var baseColor: NSColor = .labelColor
    var resultColor: MathResultColor = .automatic
    var onResultCopy: (String) -> Void = { _ in }
    var linedPaper = false
    private(set) var answerViews: [NSRange: MathAnswerTextView] = [:]
    private weak var selectedMathAnswer: MathAnswerTextView?
    private struct MathTooltip {
        var tag: NSView.ToolTipTag
        var rect: NSRect
        var text: String
    }
    private var mathTooltips: [NSRange: MathTooltip] = [:]
    var mathAnalysis = ScratchAnalysis() {
        didSet {
            let valid = Set(mathAnalysis.mathResults.filter { !$0.isHint }.map(\.range))
            for range in Array(answerViews.keys) where !valid.contains(range) {
                answerViews.removeValue(forKey: range)?.removeFromSuperview()
            }
            removeAllToolTips(); mathTooltips.removeAll(keepingCapacity: true)
            needsDisplay = true
            let spoken = mathAnalysis.mathResults.filter { !$0.isHint }.map(\.answer)
            setAccessibilityHelp(spoken.isEmpty ? nil : spoken.joined(separator: ". "))
        }
    }

    /// Math lines wrap this much earlier so their answer always has room; the
    /// rest of the note keeps its full width and never reflows.
    static let answerWidth: CGFloat = 190

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if let replacementString {
            checkboxes = checkboxes.compactMap { $0.adjusted(for: affectedCharRange, replacement: replacementString) }
        }
        if !mathAnalysis.mathResults.isEmpty, let replacementString {
            let delta = replacementString.utf16.count - affectedCharRange.length
            var updated = mathAnalysis
            updated.source = ""
            updated.mathResults = updated.mathResults.compactMap { result in
                var range = result.range
                if affectedCharRange.location > NSMaxRange(range) { return result }
                // Return at the end of the line starts a new one; this line is unchanged.
                if affectedCharRange.location == NSMaxRange(range), affectedCharRange.length == 0,
                   replacementString.first?.isNewline == true { return result }
                if NSMaxRange(affectedCharRange) <= range.location {
                    range.location += delta
                } else {
                    // A changed line keeps its last answer while recalculating.
                    // Split/merged lines wait for fresh ranges from the worker.
                    if replacementString.contains(where: \.isNewline) ||
                        (string as NSString).substring(with: affectedCharRange).contains(where: \.isNewline) { return nil }
                    range.length = max(0, range.length + delta)
                }
                return ScratchMathResult(range: range, answer: result.answer, isHint: result.isHint)
            }
            mathAnalysis = updated
        }
        return true
    }
    private(set) var checkboxes: [NoteCheckbox] = []
    private var monitor: Any?
    private var armed = false

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        selectedMathAnswer?.isActive = false
        selectedMathAnswer = nil
        let point = convert(event.locationInWindow, from: nil)
        if let box = checkboxes.first(where: { hitRect(for: $0).contains(point) }) {
            arm()
            toggle(box)
            return
        }
        arm()
        super.mouseDown(with: event)
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for box in checkboxes {
            addCursorRect(hitRect(for: box), cursor: .pointingHand)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            armed = false
            removeMonitor()
            styleTask?.cancel()
            hideSlashMenu()
        } else if focusOnAttach {
            focusOnAttach = false
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    self.arm()
                    self.needsDisplay = true
                }
            }
        }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
        if !stillSelecting { updateSlashMenu() }
    }

    override func didChangeText() {
        super.didChangeText()
        updateSlashMenu()
    }

    // MARK: Slash menu

    /// The `/command` being typed at the start of the caret's line, if any.
    private func slashQueryRange() -> NSRange? {
        guard selectedRange().length == 0 else { return nil }
        let range = rangeForUserCompletion
        guard range.location != NSNotFound, NSMaxRange(range) <= (string as NSString).length,
              (string as NSString).substring(with: range).hasPrefix("/") else { return nil }
        return range
    }

    func updateSlashMenu() {
        guard let range = slashQueryRange() else { dismissedSlash = nil; hideSlashMenu(); return }
        guard dismissedSlash != range.location else { hideSlashMenu(); return }
        let items = SlashCommand.matching((string as NSString).substring(with: range))
        guard !items.isEmpty else { hideSlashMenu(); return }
        let menu = slashMenu ?? {
            let menu = SlashMenuView(frame: .zero)
            menu.onChoose = { [weak self] in self?.chooseSlash($0) }
            addSubview(menu)
            slashMenu = menu
            return menu
        }()
        menu.textColor = baseColor
        menu.items = items
        menu.isHidden = false
        positionSlashMenu(menu, at: range)
    }

    private func positionSlashMenu(_ menu: SlashMenuView, at range: NSRange) {
        guard let layoutManager, let textContainer else { return }
        let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
        let anchor = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let size = NSSize(width: min(SlashMenuView.width, max(160, bounds.width - 8)), height: menu.preferredHeight)
        let x = max(4, min(anchor.minX - 6, bounds.width - size.width - 4))
        var y = anchor.maxY + 6
        let visible = visibleRect
        if y + size.height > visible.maxY, anchor.minY - size.height - 6 >= visible.minY {
            y = anchor.minY - size.height - 6
        }
        menu.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func hideSlashMenu() { slashMenu?.isHidden = true }

    private var slashMenuShown: Bool { slashMenu.map { !$0.isHidden } ?? false }

    private func chooseSlash(_ command: SlashCommand) {
        guard let range = slashQueryRange() else { hideSlashMenu(); return }
        hideSlashMenu()
        insertCompletion(command.name, forPartialWordRange: range, movement: NSTextMovement.return.rawValue, isFinal: true)
        updateSlashMenu()
    }

    override func doCommand(by selector: Selector) {
        if slashMenuShown, let menu = slashMenu {
            switch selector {
            case #selector(moveUp(_:)): menu.move(-1); return
            case #selector(moveDown(_:)): menu.move(1); return
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                if menu.items.indices.contains(menu.selection) { chooseSlash(menu.items[menu.selection]) }
                return
            case #selector(cancelOperation(_:)): dismissSlashMenu(); return
            default: break
            }
        }
        super.doCommand(by: selector)
    }

    @discardableResult
    func dismissSlashMenu() -> Bool {
        guard slashMenuShown, let range = slashQueryRange() else { return false }
        dismissedSlash = range.location
        hideSlashMenu()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        if linedPaper {
            baseColor.withAlphaComponent(0.1).setStroke()
            let rules = NSBezierPath()
            rules.lineWidth = 0.5
            for y in paperRulePositions(in: dirtyRect) {
                rules.move(to: NSPoint(x: textContainerInset.width, y: y))
                rules.line(to: NSPoint(x: bounds.maxX - textContainerInset.width, y: y))
            }
            rules.stroke()
        }
        super.draw(dirtyRect)
        drawCheckboxes()
        drawMathResults(in: dirtyRect)
        drawFallbackCaret()
    }

    /// Rules share document coordinates with the glyphs, including wrapped and
    /// differently sized lines. Only visible fragments and empty rows are drawn.
    func paperRulePositions(in rect: NSRect) -> [CGFloat] {
        guard let manager = layoutManager, let container = textContainer else { return [] }
        let origin = textContainerOrigin
        let glyphs = manager.glyphRange(forBoundingRect: rect.offsetBy(dx: -origin.x, dy: -origin.y), in: container)
        var positions: [CGFloat] = []
        manager.enumerateLineFragments(forGlyphRange: glyphs) { fragment, _, _, _, _ in
            let top = fragment.minY + origin.y
            let bottom = fragment.maxY + origin.y
            if positions.isEmpty, top >= rect.minY { positions.append(top) }
            if bottom >= rect.minY, bottom <= rect.maxY { positions.append(bottom) }
        }
        if NSMaxRange(glyphs) >= manager.numberOfGlyphs {
            let height = manager.defaultLineHeight(for: baseFont)
            guard height > 0 else { return positions }
            var end = positions.last ?? origin.y
            if manager.extraLineFragmentTextContainer === container {
                let extra = manager.extraLineFragmentRect.offsetBy(dx: origin.x, dy: origin.y)
                if extra.maxY > end { end = extra.maxY }
                if end >= rect.minY, end <= rect.maxY, positions.last != end { positions.append(end) }
            }
            while end < rect.minY { end += height }
            while end <= rect.maxY {
                if positions.last != end { positions.append(end) }
                end += height
            }
        }
        return positions
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        mathTooltips.values.first { $0.tag == tag }?.text ?? ""
    }

    private func drawMathResults(in dirtyRect: NSRect) {
        for range in Array(answerViews.keys) {
            if let answer = answerViews[range], !answer.frame.intersects(visibleRect) {
                answerViews.removeValue(forKey: range)?.removeFromSuperview()
            }
        }
        for (range, tooltip) in mathTooltips where !tooltip.rect.intersects(visibleRect) {
            removeToolTip(tooltip.tag); mathTooltips.removeValue(forKey: range)
        }
        guard !mathAnalysis.mathResults.isEmpty,
              let manager = layoutManager, let container = textContainer else { return }
        let visible = manager.glyphRange(forBoundingRect: dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: container)
        let visibleCharacters = manager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)
        let results = mathAnalysis.mathResults
        var lower = 0
        var upper = results.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if NSMaxRange(results[middle].range) <= visibleCharacters.location { lower = middle + 1 }
            else { upper = middle }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: baseFont.pointSize, weight: .medium),
            .foregroundColor: resultColor.resolve(textColor: baseColor), .paragraphStyle: paragraph,
        ]
        let hintAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(10, baseFont.pointSize * 0.8)),
            .foregroundColor: baseColor.withAlphaComponent(0.38), .paragraphStyle: paragraph,
        ]
        let textLength = (string as NSString).length
        for result in results.dropFirst(lower) {
            if result.range.location >= NSMaxRange(visibleCharacters) { break }
            guard result.range.length > 0, NSMaxRange(result.range) <= textLength else { continue }
            let glyph = manager.glyphIndexForCharacter(at: NSMaxRange(result.range) - 1)
            guard NSLocationInRange(glyph, visible) else { continue }
            let end = manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let x = end.maxX + textContainerOrigin.x + 12
            let width = bounds.maxX - textContainerInset.width - 4 - x
            guard width > 24 else { continue }
            let style = result.isHint ? hintAttributes : attributes
            let text = (result.isHint ? result.answer : "→ " + result.answer) as NSString
            let height = text.size(withAttributes: style).height
            // Center on the line's text so smaller hint text lines up with it.
            let used = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let rect = NSRect(x: x, y: used.midY + textContainerOrigin.y - height / 2, width: width, height: height)
            if result.isHint { text.draw(in: rect, withAttributes: style) }
            if !result.isHint {
                let arrow = "→ " as NSString
                let arrowWidth = arrow.size(withAttributes: style).width
                arrow.draw(in: NSRect(x: rect.minX, y: rect.minY, width: arrowWidth, height: rect.height), withAttributes: style)
                let answer: MathAnswerTextView
                if let existing = answerViews[result.range] { answer = existing }
                else {
                    answer = MathAnswerTextView(frame: .zero, textContainer: nil)
                    answer.onSelect = { [weak self] field in
                        self?.selectedMathAnswer?.isActive = false
                        self?.selectedMathAnswer = field
                        self?.armed = false
                        self?.needsDisplay = true
                    }
                    answer.onCopy = { [weak self] text in self?.onResultCopy(text) }
                    answerViews[result.range] = answer
                    addSubview(answer)
                }
                if answer.string != result.answer { answer.string = result.answer }
                let font = attributes[.font] as? NSFont
                let color = resultColor.resolve(textColor: baseColor)
                if answer.font != font { answer.font = font }
                if answer.textColor != color { answer.textColor = color }
                answer.frame = NSRect(x: rect.minX + arrowWidth, y: rect.minY,
                                      width: max(0, rect.width - arrowWidth), height: ceil(rect.height) + 3)
                answer.setAccessibilityLabel("Math result: \(result.answer)")
                if let old = mathTooltips[result.range], old.rect != rect {
                    removeToolTip(old.tag); mathTooltips.removeValue(forKey: result.range)
                }
                if mathTooltips[result.range] == nil {
                    let tag = addToolTip(rect, owner: self, userData: nil)
                    mathTooltips[result.range] = MathTooltip(tag: tag, rect: rect, text: result.answer)
                }
            }
            _ = line
        }
    }

    // MARK: Checkboxes

    /// Restore actor-prepared formatting in this same AppKit update, before a
    /// frame can display the replacement note as unformatted text.
    @discardableResult
    func restorePresentation(_ analysis: ScratchAnalysis) -> Bool {
        guard analysis.prepared, analysis.source == string else { return false }
        styleTask?.cancel()
        checkboxes = analysis.checkboxes
        spans = analysis.spans
        mathAnalysis = analysis
        applyStyle()
        return true
    }

    /// Notes up to this size are styled in the same edit, so new checkboxes and
    /// headings never flash as raw text first. Larger notes style off-main.
    static let immediateStyleLimit = 40_000

    func restyle() {
        styleTask?.cancel()
        let snapshot = string
        if (snapshot as NSString).length <= Self.immediateStyleLimit {
            checkboxes = NoteCheckbox.find(in: snapshot)
            spans = ScratchTextSpan.parse(snapshot)
            applyStyle()
            return
        }
        styleTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(70)) } catch { return }
            let work = Task.detached(priority: .userInitiated) { (NoteCheckbox.find(in: snapshot), ScratchTextSpan.parse(snapshot)) }
            let boxes = await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
            guard let self, !Task.isCancelled, self.string == snapshot else { return }
            self.checkboxes = boxes.0
            self.spans = boxes.1
            self.applyStyle()
        }
    }

    func clearDerivedStyle() {
        styleTask?.cancel()
        checkboxes = []; spans = []
    }

    private func applyStyle() {
        guard let storage = textStorage else { return }
        let font = baseFont
        let whole = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes([.font: font, .foregroundColor: baseColor], range: whole)
        let isCode = ScratchMode.keyword(of: string) == "code"
        if isCode { storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular), range: whole) }
        else {
            for span in spans {
                guard NSMaxRange(span.range) <= storage.length else { continue }
                switch span.kind {
                case "heading":
                    // # through ###### step down in size; the markers recede.
                    let level = (storage.string as NSString).substring(with: span.range).prefix { $0 == "#" }.count
                    let scale: [CGFloat] = [1.6, 1.38, 1.2, 1.08, 1.0, 0.92]
                    let weight: NSFont.Weight = level <= 2 ? .bold : .semibold
                    let size = (font.pointSize * scale[min(max(level, 1), 6) - 1]).rounded()
                    storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: weight), range: span.range)
                    storage.addAttribute(.foregroundColor, value: baseColor.withAlphaComponent(0.35),
                                         range: NSRange(location: span.range.location, length: level))
                    if level <= 3, span.range.location > 0 {
                        let paragraph = NSMutableParagraphStyle()
                        paragraph.paragraphSpacingBefore = (size * 0.35).rounded()
                        storage.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
                    }
                    if level == 6 { storage.addAttribute(.foregroundColor, value: baseColor.withAlphaComponent(0.7), range: NSRange(location: span.range.location + level, length: span.range.length - level)) }
                case "bold": storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: font.pointSize), range: span.range)
                case "italic": storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: span.range)
                case "underline": storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
                case "strike": storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.range)
                case "comment": storage.addAttribute(.foregroundColor, value: baseColor.withAlphaComponent(0.5), range: span.range)
                case "link": if let url = span.url { storage.addAttribute(.link, value: url, range: span.range) }
                case "code": storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular), range: span.range)
                case "keyword":
                    // Section headings read like the mode label, not like note text.
                    storage.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: max(10, font.pointSize * 0.72), weight: .semibold),
                        .foregroundColor: baseColor.withAlphaComponent(0.55), .kern: 1.5,
                    ], range: span.range)
                default: break
                }
            }
        }
        // A math section can contain prose, comments and incomplete expressions.
        // Only evaluated lines need room for an inline result.
        for result in mathAnalysis.mathResults where !result.isHint {
            guard result.range.length > 0, NSMaxRange(result.range) <= storage.length else { continue }
            let paragraph = NSMutableParagraphStyle()
            paragraph.tailIndent = -Self.answerWidth
            storage.addAttribute(.paragraphStyle, value: paragraph, range: result.range)
        }
        for box in checkboxes {
            guard NSMaxRange(box.marker) <= storage.length, NSMaxRange(box.body) <= storage.length else { continue }
            if box.implicit {
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = font.pointSize + 7
                paragraph.headIndent = font.pointSize + 7
                storage.addAttribute(.paragraphStyle, value: paragraph, range: box.body)
            } else { storage.addAttribute(.foregroundColor, value: NSColor.clear, range: box.marker) }
            // Reserve enough width for the drawn box so it cannot cover the
            // first letter of the item at larger editor font sizes.
            if box.marker.length > 0 {
                let markerWidth = (storage.string as NSString).substring(with: box.marker).size(withAttributes: [.font: font]).width
                storage.addAttribute(.kern, value: max(0, font.pointSize + 7 - markerWidth),
                                     range: NSRange(location: NSMaxRange(box.marker) - 1, length: 1))
            }
            if box.checked, box.body.length > 0 {
                storage.addAttributes([
                    .foregroundColor: baseColor.withAlphaComponent(0.45),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: box.body)
            }
        }
        storage.endEditing()
        (enclosingScrollView as? NoteScrollView)?.railNeedsReload()
        typingAttributes = [.font: font, .foregroundColor: baseColor]
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func toggle(_ box: NoteCheckbox) {
        let edit = box.toggle
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        onSave?()
    }

    private func markerRect(for box: NoteCheckbox) -> NSRect {
        guard let layoutManager, let textContainer, NSMaxRange(box.marker) <= (string as NSString).length else { return .zero }
        if box.implicit, box.body.length > 0 {
            let glyph = layoutManager.glyphIndexForCharacter(at: box.body.location)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
            return NSRect(x: rect.minX + textContainerOrigin.x - baseFont.pointSize - 7,
                          y: rect.minY + textContainerOrigin.y, width: baseFont.pointSize + 1, height: rect.height)
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: box.marker, actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private func boxRect(for box: NoteCheckbox) -> NSRect {
        let marker = markerRect(for: box)
        let side = min(max((font?.pointSize ?? 13) + 1, 12), marker.height)
        return NSRect(x: marker.minX, y: marker.midY - side / 2, width: side, height: side)
    }

    private func hitRect(for box: NoteCheckbox) -> NSRect {
        markerRect(for: box).union(boxRect(for: box)).insetBy(dx: -2, dy: -1)
    }

    private func drawCheckboxes() {
        for box in checkboxes {
            let rect = boxRect(for: box)
            guard rect.width > 0 else { continue }
            let color = box.checked ? NSColor.controlAccentColor : baseColor.withAlphaComponent(0.7)
            let name = box.checked ? "checkmark.square.fill" : "square"
            let config = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: box.checked ? "Checked" : "Unchecked")?
                .withSymbolConfiguration(config)
            else { continue }
            let size = image.size
            let target = NSRect(
                x: rect.minX,
                y: rect.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    // MARK: Keyboard

    private func drawFallbackCaret() {
        guard armed, let window, window.firstResponder !== self, selectedRange().length == 0 else { return }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard screenRect != .zero else { return }
        let local = convert(window.convertFromScreen(screenRect), from: nil)
        let height = max(local.height, font?.boundingRectForFont.height ?? 16)
        insertionPointColor.setFill()
        NSRect(x: local.minX, y: local.minY, width: 2, height: height).fill()
    }

    private func arm() {
        window?.makeFirstResponder(self)
        armed = true
        installMonitor()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.route(event) ?? false }
            return consumed ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func route(_ event: NSEvent) -> Bool {
        guard armed, let window, window.isKeyWindow, event.window === window || event.window == nil else { return false }
        if let responder = window.firstResponder as? NSTextView, responder !== self {
            armed = false
            return false
        }
        if event.keyCode == 53 {
            if dismissSlashMenu() { return true }
            if onEscape() { return true }
            armed = false
            needsDisplay = true
            return false
        }
        if event.modifierFlags.contains(.command) {
            return shortcut(event)
        }
        if window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        keyDown(with: event)
        needsDisplay = true
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if selectedMathAnswer?.isActive == true, event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c",
           (window?.firstResponder === selectedMathAnswer || window?.firstResponder === self) {
            selectedMathAnswer?.copy(nil)
            return true
        }
        // Key equivalents walk the whole view tree. While the search or find
        // field is editing, ⌘V/⌘A/⌘Z belong to that field, not this note.
        if let editing = window?.firstResponder as? NSTextView, editing !== self {
            return super.performKeyEquivalent(with: event)
        }
        if event.modifierFlags.contains(.command), shortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Route widget commands explicitly: NSHostingView shortcut registration is
    /// not reliable inside the host's nonactivating popup panels.
    private func shortcut(_ event: NSEvent) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        if shift, event.keyCode == 18 { return onShortcut("promote") } // ⌘⇧1 on any layout
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "\r":
            if let span = spans.first(where: { $0.kind == "link" && NSLocationInRange(selectedRange().location, $0.range) }), let url = span.url { onOpenURL(url) }
        case "n": return onCommand("/new")
        case "f": return shift ? onShortcut("find") : onCommand("/search")
        case "s": return onShortcut("export")
        case "d": return onShortcut("void")
        case "t": return onShortcut("swap")
        case "o" where shift: return onShortcut("popout")
        case "w": return onShortcut("close")
        case "=", "+": return onShortcut("bigger")
        case "-": return onShortcut("smaller")
        case "[": onNavigate(1)
        case "]": onNavigate(-1)
        case "b": wrapSelection("**")
        case "i": wrapSelection("*")
        case "u": wrapSelection("__")
        case "v": paste(nil)
        case "c": copy(nil)
        case "x": cut(nil)
        case "a": selectAll(nil)
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
        default: return false
        }
        return true
    }
}


extension InlineTextView {
    /// Whether this line belongs to a `list` section (the whole note or a block).
    private func inListSection(_ location: Int) -> Bool {
        ScratchMode.sections(in: string).contains { section in
            section.mode == "list" && section.lines.contains { $0.range.location == location }
        }
    }

    private static let slashCommands = SlashCommand.all.map(\.name)

    override var rangeForUserCompletion: NSRange {
        let source = string as NSString
        let cursor = selectedRange().location
        guard cursor <= source.length else { return super.rangeForUserCompletion }
        let line = source.lineRange(for: NSRange(location: cursor, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: cursor - line.location))
        if prefix.range(of: #"^\s*/[a-z]*$"#, options: .regularExpression) != nil,
           let slash = prefix.firstIndex(of: "/") {
            let offset = prefix[..<slash].utf16.count
            return NSRange(location: line.location + offset, length: cursor - line.location - offset)
        }
        return super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
        let source = string as NSString
        guard NSMaxRange(charRange) <= source.length else { return nil }
        let prefix = source.substring(with: charRange).lowercased()
        guard prefix.hasPrefix("/"), !prefix.hasPrefix("//") else {
            return super.completions(forPartialWordRange: charRange, indexOfSelectedItem: index)
        }
        index.pointee = 0
        return Self.slashCommands.filter { $0.hasPrefix(prefix) }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if let text = insertString as? String, text == "x" || text == "X" {
            checkTrigger()
        }
        if let text = insertString as? String, text == "]" { spaceAfterTypedCheckbox() }
    }

    private func checkTrigger() {
        let source = string as NSString, cursor = selectedRange().location
        guard cursor >= 2, cursor <= source.length,
              source.substring(with: NSRange(location: cursor - 2, length: 2)).lowercased() == "/x" else { return }
        let range = source.lineRange(for: NSRange(location: cursor - 2, length: 0))
        let prefix = source.substring(with: NSRange(location: range.location, length: cursor - 2 - range.location))
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"),
              ScratchMode.keyword(of: prefix).isEmpty else { return }
        let box = NoteCheckbox.find(in: prefix).first
        guard box != nil || inListSection(range.location) else { return }
        super.insertText("", replacementRange: NSRange(location: cursor - 2, length: 2))
        if let box {
            let edit = box.toggle
            super.insertText(edit.replacement, replacementRange: NSRange(location: range.location + edit.range.location, length: edit.range.length))
        } else {
            super.insertText("[x] ", replacementRange: NSRange(location: range.location, length: 0))
        }
        let newLine = (string as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        setSelectedRange(NSRange(location: NSMaxRange(newLine) - ((string as NSString).substring(with: newLine).hasSuffix("\n") ? 1 : 0), length: 0))
    }

    private static let typedCheckbox = try! NSRegularExpression(pattern: #"^[ \t]*(?:- )?\[[ xX]?\]$"#)

    /// A checkbox needs a space before its text. Typing `[]`, `[ ]` or `- [ ]`
    /// at the start of a line adds it, so "[]Milk" stays a checklist item.
    private func spaceAfterTypedCheckbox() {
        let source = string as NSString, caret = selectedRange().location
        guard selectedRange().length == 0, caret <= source.length else { return }
        let line = source.lineRange(for: NSRange(location: caret, length: 0))
        let prefix = source.substring(with: NSRange(location: line.location, length: caret - line.location))
        guard Self.typedCheckbox.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) != nil else { return }
        if caret < source.length, let next = Unicode.Scalar(source.character(at: caret)), next == " " || next == "\t" { return }
        super.insertText(" ", replacementRange: NSRange(location: caret, length: 0))
    }

    /// Choosing a command from the slash popup runs it, as Return on the line
    /// does. /timer waits for its duration instead.
    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
        let chosen = movement == NSTextMovement.return.rawValue || movement == NSTextMovement.tab.rawValue
        guard flag, chosen, word.hasPrefix("/") else { return }
        if word == "/timer" { super.insertText(" ", replacementRange: selectedRange()); return }
        let source = string as NSString
        let lineRange = source.lineRange(for: NSRange(location: charRange.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard line.trimmingCharacters(in: .whitespaces) == word else { return }
        if !executeSlash(line, range: lineRange) { _ = onCommand(word) }
    }

    private func executeSlash(_ line: String, range: NSRange) -> Bool {
        let command = line.trimmingCharacters(in: .whitespaces).lowercased()
        guard command.hasPrefix("/"), !command.hasPrefix("//") else { return false }
        let modes = ["list", "math", "sum", "average", "count", "code", "text"]
        if command.hasPrefix("/"), modes.contains(String(command.dropFirst())) {
            // A mode starts a section on this line that runs to the next blank
            // line; the rest of the note is untouched. /text ends a section.
            let mode = String(command.dropFirst())
            // /list starts a checklist item right here, like typing [].
            let replacement = mode == "list" ? "[] " : mode == "text" ? "\n" : mode + "\n"
            insertText(replacement,
                       replacementRange: NSRange(location: range.location, length: (line as NSString).length))
            return true
        }
        let replacements = ["/checkbox": "[] ", "/bullet": "- ", "/numbered": "1. ",
                            "/date": Date().formatted(date: .numeric, time: .omitted),
                            "/time": Date().formatted(date: .omitted, time: .shortened)]
        if let replacement = replacements[command] {
            insertText(replacement, replacementRange: NSRange(location: range.location, length: (line as NSString).length))
            return true
        }
        let name = command.split(separator: " ").first.map(String.init) ?? ""
        if ["/new", "/search", "/copy", "/paste", "/timer", "/import", "/export"].contains(name) {
            if name == "/timer", ScratchTimerCommand.parse(String(command.dropFirst())) == nil,
               !["/timer p", "/timer r", "/timer s", "/timer 0"].contains(command) { return false }
            insertText("", replacementRange: NSRange(location: range.location, length: (line as NSString).length))
            return onCommand(line.trimmingCharacters(in: .whitespaces))
        }
        return false
    }

    private enum ImageDrop { case file(URL), data(Data) }

    /// Plain-text views accept file drags by inserting the path, so image
    /// drops have to be claimed here before NSTextView handles them.
    private func imageDrop(_ info: NSDraggingInfo) -> ImageDrop? {
        let board = info.draggingPasteboard
        if let url = Self.imageFile(on: board) { return .file(url) }
        if board.string(forType: .string) != nil { return nil }
        return (board.data(forType: .png) ?? board.data(forType: .tiff)).map(ImageDrop.data)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageDrop(sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        imageDrop(sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        switch imageDrop(sender) {
        case .file(let url): onImageFile(url); return true
        case .data(let data): onImage(data); return true
        case nil: return super.performDragOperation(sender)
        }
    }

    private static func imageFile(on board: NSPasteboard) -> URL? {
        board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ])?.first as? URL
    }

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        // A copied image file also carries its name as text; recognize the image instead.
        if let url = Self.imageFile(on: board) { onImageFile(url); return }
        if let text = board.string(forType: .string) {
            let caret = selectedRange().location
            let isCode = ScratchMode.keyword(of: string) == "code" || ScratchMode.sections(in: string).contains { section in
                section.mode == "code" && section.lines.contains { NSLocationInRange(caret, $0.range) || caret == NSMaxRange($0.range) }
            }
            let plain = isCode ? text : text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            insertText(plain, replacementRange: selectedRange())
        } else if let data = board.data(forType: .png) ?? board.data(forType: .tiff) { onImage(data) }
        else if let url = NSURL(from: board) as URL?, url.isFileURL { onImageFile(url) }
    }

    override func insertNewline(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        if executeSlash(line, range: lineRange) { return }
        if onCommand(line) { super.insertNewline(sender); return }
        if let match = Self.listItem.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
            let indent = (line as NSString).substring(with: match.range(at: 1))
            var marker = (line as NSString).substring(with: match.range(at: 2))
                .replacingOccurrences(of: "[x]", with: "[ ]").replacingOccurrences(of: "[X]", with: "[ ]")
            if let number = Int(marker.dropLast()), marker.hasSuffix(".") { marker = "\(number + 1)." }
            if (line as NSString).length == match.range.length {
                insertText("", replacementRange: NSRange(location: lineRange.location, length: match.range.length))
            } else { insertText("\n" + indent + marker + " ", replacementRange: selection) }
        } else { super.insertNewline(sender) }
    }

    private static let listItem = try! NSRegularExpression(pattern: #"^(\s*)(- \[[ xX]\]|\[[ xX]\]|\[\]|[-*]|\d+\.)\s+"#)

    /// Start offsets of the lines the selection touches, last first so earlier
    /// edits do not shift later ones.
    private func selectedLineStarts() -> [Int] {
        let source = string as NSString
        let lines = source.lineRange(for: selectedRange())
        var starts: [Int] = []
        var offset = lines.location
        repeat {
            starts.append(offset)
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0)))
        } while offset < NSMaxRange(lines)
        return starts.reversed()
    }

    /// Tab nests list items (and multi-line selections) from the line start;
    /// elsewhere it inserts spaces at the caret.
    override func insertTab(_ sender: Any?) {
        let source = string as NSString
        let selection = selectedRange()
        let line = source.substring(with: source.lineRange(for: NSRange(location: selection.location, length: 0)))
        let isItem = Self.listItem.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
        guard isItem || source.substring(with: selection).contains(where: \.isNewline) else {
            insertText("    ", replacementRange: selection); return
        }
        let starts = selectedLineStarts()
        undoManager?.beginUndoGrouping()
        for start in starts { insertText("    ", replacementRange: NSRange(location: start, length: 0)) }
        undoManager?.endUndoGrouping()
        setSelectedRange(NSRange(location: selection.location + 4, length: max(0, selection.length + 4 * (starts.count - 1))))
    }

    override func insertBacktab(_ sender: Any?) {
        let selection = selectedRange()
        var removed = 0, removedOnFirst = 0
        let starts = selectedLineStarts()
        undoManager?.beginUndoGrouping()
        for start in starts {
            let source = string as NSString
            let line = source.substring(with: source.lineRange(for: NSRange(location: start, length: 0)))
            let count = line.prefix(4).prefix(while: { $0 == " " }).count
            guard count > 0 else { continue }
            insertText("", replacementRange: NSRange(location: start, length: count))
            removed += count
            if start <= selection.location { removedOnFirst = count }
        }
        undoManager?.endUndoGrouping()
        let location = max(starts.last ?? 0, selection.location - removedOnFirst)
        setSelectedRange(NSRange(location: location, length: max(0, selection.length - (removed - removedOnFirst))))
    }

    func wrapSelection(_ marker: String) {
        let range = selectedRange(), source = string as NSString
        let value = source.substring(with: range)
        insertText(marker + value + marker, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + marker.count, length: range.length))
    }
}

/// Trackpad scrolling is delivered to the scroll view before the text view.
/// Keep its vertical behavior and reserve deliberate horizontal gestures for
/// note navigation, committing only after fingers lift (never on momentum).
@MainActor
final class NoteScrollView: NSScrollView {
    var onNavigate: (Int) -> Void = { _ in }
    private var swipeTracker = NoteSwipeTracker()
    let rail = NoteScrollRail()
    private var reloadScheduled = false
    nonisolated(unsafe) private var boundsObserver: NSObjectProtocol?

    func attachRail(to textView: NSTextView) {
        rail.textView = textView
        rail.color = (textView as? InlineTextView)?.baseColor ?? .labelColor
        rail.onJump = { [weak self] y, animated in self?.scroll(toY: y, animated: animated) }
        addSubview(rail)
        addSubview(rail.card)
        contentView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rail.refreshPositions() }
        }
        tile()
        railNeedsReload()
    }

    /// Coalesces edits and restyles into one outline rebuild per run loop turn.
    func railNeedsReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reloadScheduled = false
                self.rail.reload()
            }
        }
    }

    /// The rail's strip is always reserved, so text never reflows when the
    /// note becomes long enough to show ticks.
    override func tile() {
        super.tile()
        guard rail.superview === self else { return }
        var clip = contentView.frame
        clip.size.width = max(0, bounds.width - NoteScrollRail.width)
        contentView.frame = clip
        if let editor = documentView as? InlineTextView {
            editor.minSize = NSSize(width: 0, height: clip.height)
            if editor.frame.height < clip.height {
                editor.setFrameSize(NSSize(width: clip.width, height: clip.height))
            }
            editor.needsDisplay = true
        }
        rail.frame = NSRect(x: bounds.width - NoteScrollRail.width, y: 0, width: NoteScrollRail.width, height: bounds.height)
        rail.refreshPositions()
    }

    func scroll(toY y: CGFloat, animated: Bool) {
        guard let document = documentView else { return }
        let limit = max(0, document.frame.height - contentView.bounds.height)
        let target = NSPoint(x: contentView.bounds.minX, y: min(max(0, y - 10), limit))
        guard animated else {
            contentView.setBoundsOrigin(target)
            reflectScrolledClipView(contentView)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.allowsImplicitAnimation = true
            contentView.animator().setBoundsOrigin(target)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reflectScrolledClipView(self.contentView)
                self.rail.refreshPositions()
            }
        }
    }

    override func scrollWheel(with event: NSEvent) {
        switch swipeTracker.step(x: event.scrollingDeltaX, y: event.scrollingDeltaY,
                                phase: event.phase, momentum: event.momentumPhase,
                                precise: event.hasPreciseScrollingDeltas) {
        case .passThrough: super.scrollWheel(with: event)
        case .consume: break
        case .navigate(let direction): onNavigate(direction)
        }
    }

    override func swipe(with event: NSEvent) {
        if abs(event.deltaX) > abs(event.deltaY), event.deltaX != 0 {
            onNavigate(event.deltaX > 0 ? -1 : 1)
        } else { super.swipe(with: event) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { swipeTracker = NoteSwipeTracker(); rail.hover(nil) }
    }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }
}

struct NoteSwipeTracker {
    enum Action: Equatable { case passThrough, consume, navigate(Int) }
    private enum Axis { case undecided, horizontal, vertical }
    private var axis = Axis.undecided
    private var distanceX: CGFloat = 0
    private var distanceY: CGFloat = 0
    private var tracking = false

    mutating func step(x: CGFloat, y: CGFloat, phase: NSEvent.Phase,
                       momentum: NSEvent.Phase = [], precise: Bool = true) -> Action {
        if phase.contains(.began) || phase.contains(.mayBegin) {
            self = NoteSwipeTracker()
            tracking = true
        }
        if !momentum.isEmpty { return axis == .horizontal ? .consume : .passThrough }
        guard precise, tracking, !phase.isEmpty else { return .passThrough }
        if phase.contains(.cancelled) {
            let handled = axis == .horizontal
            self = NoteSwipeTracker()
            return handled ? .consume : .passThrough
        }
        distanceX += x
        distanceY += y
        if axis == .undecided, max(abs(distanceX), abs(distanceY)) >= 16 {
            axis = abs(distanceX) > abs(distanceY) * 2 ? .horizontal : .vertical
        }
        if phase.contains(.ended) {
            tracking = false
            // Swiping left goes to the older note (direction 1), right to the newer one.
            if axis == .horizontal, abs(distanceX) >= 120 {
                return .navigate(distanceX > 0 ? -1 : 1)
            }
        }
        return axis == .horizontal ? .consume : .passThrough
    }
}


struct ScratchTextSpan: Equatable, Sendable {
    var range: NSRange
    var kind: String
    var url: URL?
    static func parse(_ text: String) -> [Self] {
        var result: [Self] = []
        let range = NSRange(location: 0, length: (text as NSString).length)
        for section in ScratchMode.sections(in: text) {
            if section.keyword.length > 0 { result.append(Self(range: section.keyword, kind: "keyword")) }
            if section.mode == "code" && !section.wholeNote {
                result += section.lines.map { Self(range: $0.range, kind: "code") }
            }
            if section.mode == "math" {
                result += section.lines.filter { $0.range.length > 0 }.map { Self(range: $0.range, kind: "answer") }
            }
        }
        let patterns = [("heading", #"^#{1,6} .*$"#), ("bold", #"\*\*[^\n*]+\*\*"#), ("italic", #"(?<!\*)\*[^\n*]+\*(?!\*)"#), ("underline", #"__[^\n_]+__"#), ("strike", #"~~[^\n~]+~~"#), ("comment", #"^\s*//.*$"#)]
        for (kind, pattern) in patterns {
            guard !Task.isCancelled else { return [] }
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                result += regex.matches(in: text, range: range).map { Self(range: $0.range, kind: kind) }
            }
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            result += detector.matches(in: text, range: range).compactMap { match in
                guard let url = match.url, ["http", "https"].contains(url.scheme ?? "") else { return nil }
                return Self(range: match.range, kind: "link", url: url)
            }
        }
        return result
    }
}
