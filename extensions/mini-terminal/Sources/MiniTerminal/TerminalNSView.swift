import AppKit
import MiniTerminalCore

/// Draws a terminal session and turns keys, the mouse and drops into input. Everything is drawn here with plain
/// text drawing, and only while something changes; there is no animation loop except the cursor blink, and that
/// runs only while the terminal has keyboard focus.
@MainActor
final class TerminalNSView: NSView {
    weak var session: TerminalSession? {
        didSet {
            oldValue?.onDisplay = nil
            session?.onDisplay = { [weak self] in self?.sessionChanged() }
            scrollOffset = 0; selection = nil
            lastScrollbackCount = session?.emulator.scrollback.count ?? 0
            needsLayout = true; needsDisplay = true
        }
    }

    var theme: TerminalTheme = .mono { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 10.5 { didSet { updateMetrics(); needsLayout = true; needsDisplay = true } }

    private var font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    private var boldFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    private var italicFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
    private var cellSize = CGSize(width: 6.6, height: 14)
    private let padding = NSEdgeInsets(top: 1, left: 2, bottom: 1, right: 2)

    private var scrollOffset = 0
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollbackCount = 0
    private var selection: (anchor: (row: Int, col: Int), head: (row: Int, col: Int))?
    private var blinkOn = true
    private var blinkTimer: Timer?
    private var isFocused = false
    private var dropHighlight = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL])
        updateMetrics()
        setAccessibilityRole(.textArea)
        setAccessibilityLabel("Terminal")
    }

    private func updateMetrics() {
        font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        boldFont = .monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
        italicFont = NSFont(descriptor: descriptor, size: fontSize) ?? font
        let width = ("M" as NSString).size(withAttributes: [.font: font]).width
        cellSize = CGSize(width: width, height: ceil(font.ascender - font.descender + font.leading) + 1)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let cols = max(20, Int((bounds.width - padding.left - padding.right) / cellSize.width))
        let rows = max(2, Int((bounds.height - padding.top - padding.bottom) / cellSize.height))
        session?.ensureStarted(cols: cols, rows: rows)
        session?.resize(cols: cols, rows: rows)
    }

    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
        guard let window else { stopBlink(); return }
        // If the Notch's window becomes key after the tab is already showing (it can, while it is still
        // opening), take the keyboard then rather than leaving keystrokes to go to another app.
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.claimKeyboard(activateApp: false) }
        }
        focus()
    }

    deinit {
        MainActor.assumeIsolated {
            if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
            blinkTimer?.invalidate()
        }
    }

    /// Asks for keyboard focus now and again as the Notch finishes opening. Being first responder is not enough:
    /// the window itself has to be the key window, or typing lands in whatever app is in front.
    func focus() {
        let attempts: [(delay: Double, activate: Bool)] = [(0, false), (0.05, false), (0.15, false), (0.35, false), (0.8, true)]
        for attempt in attempts {
            DispatchQueue.main.asyncAfter(deadline: .now() + attempt.delay) { [weak self] in
                MainActor.assumeIsolated { self?.claimKeyboard(activateApp: attempt.activate) }
            }
        }
    }

    private func claimKeyboard(activateApp: Bool) {
        guard let window, window.isVisible else { return }
        // Don't take focus from a text field the user is typing in (the history search, for example).
        if window.firstResponder is NSTextView, window.firstResponder !== self { return }
        if !window.isKeyWindow {
            if window.canBecomeKey { window.makeKey() }
            // As a last resort, bring Vehla forward so the window can become key.
            if activateApp, !window.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                if window.canBecomeKey { window.makeKey() }
            }
        }
        if window.firstResponder !== self { window.makeFirstResponder(self) }
    }

    private func sessionChanged() {
        guard let emulator = session?.emulator else { return }
        let count = emulator.scrollback.count
        if scrollOffset > 0 { scrollOffset += max(0, count - lastScrollbackCount) }
        lastScrollbackCount = count
        scrollOffset = min(scrollOffset, emulator.scrollbackCount)
        needsDisplay = true
    }

    // MARK: Focus and blinking

    override func becomeFirstResponder() -> Bool {
        isFocused = true
        blinkOn = true
        startBlink()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isFocused = false
        stopBlink()
        needsDisplay = true
        return true
    }

    private func startBlink() {
        stopBlink()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Nothing to blink while the Notch is closed or covered.
                guard let window = self.window, window.isVisible, window.occlusionState.contains(.visible) else { return }
                self.blinkOn.toggle()
                self.setNeedsDisplay(self.cursorRect().insetBy(dx: -2, dy: -2))
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func stopBlink() { blinkTimer?.invalidate(); blinkTimer = nil }

    // MARK: Geometry

    private func cursorRect() -> NSRect {
        guard let e = session?.emulator else { return .zero }
        return NSRect(x: padding.left + CGFloat(e.cursorCol) * cellSize.width, y: padding.top + CGFloat(e.cursorRow) * cellSize.height,
                      width: cellSize.width, height: cellSize.height)
    }

    /// Absolute row/column under a point.
    private func position(at point: NSPoint) -> (row: Int, col: Int) {
        guard let e = session?.emulator else { return (0, 0) }
        let col = max(0, min(e.cols - 1, Int((point.x - padding.left) / cellSize.width)))
        let r = max(0, min(e.rows - 1, Int((point.y - padding.top) / cellSize.height)))
        return (e.scrollbackCount - min(scrollOffset, e.scrollbackCount) + r, col)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let emulator = session?.emulator else { return }
        let history = emulator.scrollbackCount
        let offset = min(scrollOffset, history)
        for r in 0..<emulator.rows {
            let y = padding.top + CGFloat(r) * cellSize.height
            if y + cellSize.height < dirtyRect.minY || y > dirtyRect.maxY { continue }
            drawRow(emulator.line(absolute: history - offset + r), absolute: history - offset + r, y: y, cols: emulator.cols)
        }
        if offset == 0, emulator.cursorVisible { drawCursor(emulator) }
        if offset > 0 || history > 0 { drawScrollIndicator(history: history, offset: offset, rows: emulator.rows) }
        if dropHighlight {
            theme.foreground.withAlphaComponent(0.5).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            path.lineWidth = 1.5
            path.setLineDash([4, 3], count: 2, phase: 0)
            path.stroke()
        }
    }

    private func isSelected(_ row: Int, _ col: Int) -> Bool {
        guard let s = selection else { return false }
        let (a, b) = (s.anchor.row, s.anchor.col) <= (s.head.row, s.head.col) ? (s.anchor, s.head) : (s.head, s.anchor)
        return (row, col) >= (a.row, a.col) && (row, col) <= (b.row, b.col)
    }

    private struct Style: Equatable {
        var fg: NSColor
        var bold: Bool, italic: Bool, underline: Bool, strike: Bool
    }

    private func drawRow(_ cells: [TermCell], absolute: Int, y: CGFloat, cols: Int) {
        var run = ""
        var runStart = 0
        var runStyle: Style?

        func flush() {
            guard let style = runStyle, !run.isEmpty else { run = ""; runStyle = nil; return }
            var attrs: [NSAttributedString.Key: Any] = [
                .font: style.bold ? boldFont : (style.italic ? italicFont : font),
                .foregroundColor: style.fg,
            ]
            if let glow = theme.glow {
                let shadow = NSShadow()
                shadow.shadowColor = glow.withAlphaComponent(0.55)
                shadow.shadowBlurRadius = 3.5
                shadow.shadowOffset = .zero
                attrs[.shadow] = shadow
            }
            if style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            (run as NSString).draw(at: NSPoint(x: padding.left + CGFloat(runStart) * cellSize.width, y: y + 1), withAttributes: attrs)
            run = ""; runStyle = nil
        }

        for col in 0..<min(cols, cells.count) {
            let cell = cells[col]
            if cell.width == 0 { continue }
            let (fg, bg) = colors(for: cell)
            let x = padding.left + CGFloat(col) * cellSize.width
            let width = cellSize.width * CGFloat(max(1, cell.width))
            if let bg { bg.setFill(); NSRect(x: x, y: y, width: width, height: cellSize.height).fill() }
            if isSelected(absolute, col) {
                theme.selection.setFill()
                NSRect(x: x, y: y, width: width, height: cellSize.height).fill()
            }
            if cell.scalar == 0x20 && !cell.attrs.contains(.underline) { flush(); continue }
            if cell.attrs.contains(.hidden) { continue }
            let style = Style(fg: fg, bold: cell.attrs.contains(.bold), italic: cell.attrs.contains(.italic),
                              underline: cell.attrs.contains(.underline), strike: cell.attrs.contains(.strike))
            if cell.width > 1 || runStyle != style || run.isEmpty == false && col != runStart + run.count {
                flush()
            }
            if run.isEmpty { runStart = col; runStyle = style }
            run.append(cell.character)
            if cell.width > 1 { flush() }
        }
        flush()
    }

    private func colors(for cell: TermCell) -> (NSColor, NSColor?) {
        let bold = cell.attrs.contains(.bold)
        var fg = theme.resolve(cell.fg, foreground: true, bright: bold) ?? theme.foreground
        var bg = theme.resolve(cell.bg, foreground: false, bright: false)
        if cell.attrs.contains(.inverse) {
            let newBG = fg
            fg = bg.map { _ in theme.resolve(cell.bg, foreground: true, bright: false) ?? .black } ?? .black
            bg = newBG
        }
        if cell.attrs.contains(.dim) { fg = fg.withAlphaComponent(0.55) }
        return (fg, bg)
    }

    private func drawCursor(_ emulator: TerminalEmulator) {
        let rect = cursorRect()
        if isFocused {
            guard blinkOn else { return }
            theme.cursor.setFill()
            rect.fill()
            let cell = emulator.cell(row: emulator.cursorRow, col: emulator.cursorCol)
            if cell.scalar != 0x20 {
                (String(cell.character) as NSString).draw(at: NSPoint(x: rect.minX, y: rect.minY + 1),
                                                         withAttributes: [.font: font, .foregroundColor: NSColor.black])
            }
        } else {
            theme.cursor.withAlphaComponent(0.7).setStroke()
            let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawScrollIndicator(history: Int, offset: Int, rows: Int) {
        guard history > 0 else { return }
        let total = CGFloat(history + rows)
        let trackHeight = bounds.height - 6
        let thumb = max(14, trackHeight * CGFloat(rows) / total)
        let progress = 1 - CGFloat(offset) / CGFloat(max(1, history))
        let y = 3 + (trackHeight - thumb) * progress
        theme.foreground.withAlphaComponent(offset > 0 ? 0.45 : 0.14).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.width - 4, y: y, width: 2, height: thumb), xRadius: 1, yRadius: 1).fill()
    }

    // MARK: Keyboard

    /// Command shortcuts are offered here first. Handling them here (and not only in keyDown) means Paste, Copy,
    /// Clear and Select All work even when the window or app would otherwise claim the key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": pasteFromClipboard(); return true
        case "c": if selectedText() != nil { copySelection(); return true }; return false
        case "k": clearScreen(); return true
        case "a": selectEverything(); return true
        default: return false
        }
    }

    // The standard responder-chain actions, so the Edit menu and other routes can reach us too.
    @objc func paste(_ sender: Any?) { pasteFromClipboard() }
    @objc func copy(_ sender: Any?) { copySelection() }
    override func selectAll(_ sender: Any?) { selectEverything() }

    override func keyDown(with event: NSEvent) {
        guard let session else { return }
        let flags = event.modifierFlags
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": copySelection(); return
            case "v": pasteFromClipboard(); return
            case "k": session.clear(); scrollOffset = 0; needsDisplay = true; return
            case "a": selectEverything(); return
            default: super.keyDown(with: event); return
            }
        }
        var modifiers: KeyModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }

        let key: TerminalKey?
        switch event.keyCode {
        case 36, 76: key = .enter
        case 48: key = flags.contains(.shift) ? .backTab : .tab
        case 51: key = .backspace
        case 117: key = .forwardDelete
        case 53: key = .escape
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        case 115: key = .home
        case 119: key = .end
        case 116: key = .pageUp
        case 121: key = .pageDown
        case 122: key = .function(1)
        case 120: key = .function(2)
        case 99: key = .function(3)
        case 118: key = .function(4)
        case 96: key = .function(5)
        case 97: key = .function(6)
        case 98: key = .function(7)
        case 100: key = .function(8)
        case 101: key = .function(9)
        case 109: key = .function(10)
        case 103: key = .function(11)
        case 111: key = .function(12)
        default:
            // Control and Option act on the key itself, not the character it would type.
            let text = (modifiers.contains(.control) || modifiers.contains(.option) ? event.charactersIgnoringModifiers : event.characters) ?? ""
            key = text.isEmpty ? nil : .character(text)
        }
        guard let key else { return }
        scrollOffset = 0
        selection = nil
        session.sendKey(key, modifiers: modifiers)
        needsDisplay = true
    }

    // MARK: Clipboard

    func selectedText() -> String? {
        guard let s = selection, let emulator = session?.emulator else { return nil }
        let text = emulator.text(from: s.anchor, to: s.head)
        return text.isEmpty ? nil : text
    }

    @objc func copySelection() {
        guard let text = selectedText() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func pasteFromClipboard() {
        guard let text = TerminalSession.pasteText() else { NSSound.beep(); return }
        session?.paste(text)
        scrollOffset = 0
    }

    @objc func clearScreen() { session?.clear(); scrollOffset = 0; needsDisplay = true }

    @objc func copyLastOutput() { session?.copyLastOutput() }

    private func selectEverything() {
        guard let e = session?.emulator else { return }
        selection = ((0, 0), (e.totalRows - 1, max(0, e.cols - 1)))
        needsDisplay = true
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let pos = position(at: point)
        if event.modifierFlags.contains(.command), let url = url(at: pos) {
            NSWorkspace.shared.open(url)
            return
        }
        switch event.clickCount {
        case 2:
            let range = wordRange(at: pos)
            selection = ((pos.row, range.lowerBound), (pos.row, range.upperBound))
        case 3:
            selection = ((pos.row, 0), (pos.row, max(0, (session?.emulator.cols ?? 1) - 1)))
        default:
            selection = (pos, pos)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var s = selection else { return }
        s.head = position(at: convert(event.locationInWindow, from: nil))
        selection = s
        autoscroll(for: event.locationInWindow)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let s = selection, s.anchor == s.head, event.clickCount == 1 { selection = nil; needsDisplay = true }
    }

    private func autoscroll(for locationInWindow: NSPoint) {
        guard let e = session?.emulator else { return }
        let y = convert(locationInWindow, from: nil).y
        if y < 0 { scrollOffset = min(e.scrollbackCount, scrollOffset + 1) }
        else if y > bounds.height { scrollOffset = max(0, scrollOffset - 1) }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let e = session?.emulator else { return }
        let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8)
        if e.isAlternateScreen {
            // Full-screen programs without mouse support (less, man) scroll with the arrow keys.
            scrollAccumulator += delta
            let steps = Int(scrollAccumulator / (cellSize.height * 1.5))
            if steps != 0 {
                scrollAccumulator -= CGFloat(steps) * cellSize.height * 1.5
                for _ in 0..<abs(steps) { session?.sendKey(steps > 0 ? .up : .down, modifiers: []) }
            }
            return
        }
        scrollAccumulator += delta
        let rows = Int(scrollAccumulator / cellSize.height)
        if rows != 0 {
            scrollAccumulator -= CGFloat(rows) * cellSize.height
            scrollOffset = max(0, min(e.scrollbackCount, scrollOffset + rows))
            needsDisplay = true
        }
    }

    private func wordRange(at pos: (row: Int, col: Int)) -> ClosedRange<Int> {
        guard let e = session?.emulator else { return pos.col...pos.col }
        let cells = e.line(absolute: pos.row)
        func isWord(_ i: Int) -> Bool {
            guard i >= 0, i < cells.count else { return false }
            let c = cells[i].character
            return !c.isWhitespace && !"()[]{}<>\"'`,;".contains(c)
        }
        guard isWord(pos.col) else { return pos.col...pos.col }
        var lo = pos.col, hi = pos.col
        while isWord(lo - 1) { lo -= 1 }
        while isWord(hi + 1) { hi += 1 }
        return lo...hi
    }

    /// An http(s) link under the pointer, opened with Cmd-click.
    private func url(at pos: (row: Int, col: Int)) -> URL? {
        guard let e = session?.emulator else { return nil }
        let cells = e.line(absolute: pos.row)
        var text = "", columns: [Int] = []
        for (i, cell) in cells.enumerated() where cell.width != 0 { text.append(cell.character); columns.append(i) }
        guard let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"')\]]+"#) else { return nil }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let lower = columns[match.range.location], upper = columns[min(columns.count - 1, match.range.location + match.range.length - 1)]
            if (lower...upper).contains(pos.col) {
                var s = ns.substring(with: match.range)
                while let last = s.last, ".,;:!?".contains(last) { s.removeLast() }
                if let url = URL(string: s), ["http", "https"].contains(url.scheme) { return url }
            }
        }
        return nil
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copy = menu.addItem(withTitle: "Copy", action: #selector(copySelection), keyEquivalent: "")
        copy.isEnabled = selectedText() != nil
        menu.addItem(withTitle: "Paste", action: #selector(pasteFromClipboard), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Copy Last Output", action: #selector(copyLastOutput), keyEquivalent: "")
        menu.addItem(withTitle: "Clear", action: #selector(clearScreen), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    // MARK: Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHighlight = true; needsDisplay = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlight = false; needsDisplay = true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlight = false; needsDisplay = true
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        session?.paste(urls.map { ShellQuote.quote($0.path) }.joined(separator: " ") + " ")
        focus()
        return true
    }
}
