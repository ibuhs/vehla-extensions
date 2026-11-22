import Foundation

/// Collects the plain text a command prints, so its output can be copied without escape codes.
struct CaptureLog {
    private var lines: [[Character]] = [[]]
    private var column = 0
    private var total = 0
    static let limit = 200_000

    mutating func write(_ ch: Character) {
        guard total < Self.limit else { return }
        let last = lines.count - 1
        if column < lines[last].count { lines[last][column] = ch }
        else { lines[last].append(ch); total += 1 }
        column += 1
    }
    mutating func newline() { guard total < Self.limit else { return }; lines.append([]); column = 0 }
    mutating func carriageReturn() { column = 0 }
    mutating func backspace() { column = max(0, column - 1) }

    var text: String {
        var out = lines.map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }
}

/// A VT100/xterm-style terminal emulator: a grid of cells, scrollback, colours, cursor addressing, scroll
/// regions, the alternate screen, and the shell-integration marks (OSC 7 / 133 / 7777) the Notch uses.
public final class TerminalEmulator {
    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var cursorRow = 0
    public private(set) var cursorCol = 0
    public private(set) var cursorVisible = true
    public private(set) var applicationCursorKeys = false
    public private(set) var bracketedPaste = false
    public private(set) var isAlternateScreen = false
    /// Increases whenever anything visible may have changed.
    public private(set) var version = 0
    public private(set) var scrollback: [[TermCell]] = []
    public var scrollbackLimit = 2000
    public private(set) var lastOutput = ""
    public private(set) var isCapturing = false

    public var onEvent: ((TerminalEvent) -> Void)?
    /// Bytes the terminal must send back to the program (cursor position reports and the like).
    public var onResponse: (([UInt8]) -> Void)?

    // Screen state
    private var screen: [[TermCell]]
    private var savedPrimary: [[TermCell]]?
    private var savedPrimaryCursor: (row: Int, col: Int)?
    private var pen = TermCell()
    private var pendingWrap = false
    private var scrollTop = 0
    private var scrollBottom: Int
    private var tabStops: Set<Int> = []
    private var savedCursor: (row: Int, col: Int, pen: TermCell, origin: Bool) = (0, 0, TermCell(), false)

    // Modes
    private var autowrap = true
    private var originMode = false
    private var insertMode = false
    private var newlineMode = false

    // Charsets
    private var g0Graphics = false, g1Graphics = false, shifted = false

    // Parser
    private enum State { case ground, escape, escapeIntermediate, csi, osc, ignoreString }
    private var state = State.ground
    private var csiBytes: [UInt8] = []
    private var oscBytes: [UInt8] = []
    private var utf8Pending: [UInt8] = []
    private var utf8Needed = 0

    private var capture: CaptureLog?

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(1, cols); self.rows = max(1, rows)
        scrollBottom = self.rows - 1
        screen = []
        screen = (0..<self.rows).map { _ in blankLine() }
        resetTabs()
    }

    // MARK: Reading the screen

    public func cell(row: Int, col: Int) -> TermCell {
        guard row >= 0, row < screen.count, col >= 0, col < screen[row].count else { return TermCell() }
        return screen[row][col]
    }

    /// Rows above the screen that can be scrolled back to (none on the alternate screen).
    public var scrollbackCount: Int { isAlternateScreen ? 0 : scrollback.count }
    public var totalRows: Int { scrollbackCount + rows }

    /// A line by absolute index: scrollback first, then the live screen.
    public func line(absolute index: Int) -> [TermCell] {
        let history = scrollbackCount
        if index < 0 { return [] }
        if index < history { return scrollback[index] }
        let r = index - history
        return r < screen.count ? screen[r] : []
    }

    public func text(row: Int) -> String { lineText(screen[max(0, min(rows - 1, row))]) }

    private func lineText(_ cells: [TermCell]) -> String {
        var s = ""
        for c in cells where c.width != 0 { s.append(c.character) }
        while s.last == " " { s.removeLast() }
        return s
    }

    /// The last row on screen that has any text, handy for showing progress in a small space.
    public var lastNonEmptyLine: String? {
        for r in stride(from: rows - 1, through: 0, by: -1) {
            let t = lineText(screen[r]).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Text between two absolute positions (inclusive), as it would be copied.
    public func text(from a: (row: Int, col: Int), to b: (row: Int, col: Int)) -> String {
        let (start, end) = (a.row, a.col) <= (b.row, b.col) ? (a, b) : (b, a)
        var out: [String] = []
        for r in start.row...max(start.row, end.row) {
            let cells = line(absolute: r)
            let from = r == start.row ? start.col : 0
            let to = r == end.row ? min(end.col, cells.count - 1) : cells.count - 1
            guard from <= to, from < cells.count else { out.append(""); continue }
            out.append(lineText(Array(cells[from...to])))
        }
        return out.joined(separator: "\n")
    }

    // MARK: Feeding

    public func feed(_ data: Data) { feed([UInt8](data)) }

    public func feed(_ bytes: [UInt8]) {
        for byte in bytes { process(byte) }
        version &+= 1
    }

    public func feed(_ string: String) { feed(Array(string.utf8)) }

    private func process(_ b: UInt8) {
        switch state {
        case .ground: ground(b)
        case .escape: escape(b)
        case .escapeIntermediate:
            // The byte after "ESC (" / "ESC )" designates a character set: "0" is DEC line drawing.
            if pendingCharset == 0 { g0Graphics = b == UInt8(ascii: "0") }
            else if pendingCharset == 1 { g1Graphics = b == UInt8(ascii: "0") }
            state = .ground
        case .csi: csi(b)
        case .osc: osc(b)
        case .ignoreString:
            if b == 0x1B { state = .escape } else if b == 0x07 { state = .ground }
        }
    }

    // MARK: Ground (text and C0)

    private func ground(_ b: UInt8) {
        if utf8Needed > 0 {
            if b & 0xC0 == 0x80 {
                utf8Pending.append(b)
                utf8Needed -= 1
                if utf8Needed == 0 {
                    let s = String(decoding: utf8Pending, as: UTF8.self)
                    utf8Pending = []
                    for u in s.unicodeScalars { put(u.value) }
                }
                return
            }
            utf8Pending = []; utf8Needed = 0
            put(0xFFFD)
        }
        switch b {
        case 0x1B: state = .escape
        case 0x07: onEvent?(.bell)
        case 0x08: if cursorCol > 0 { cursorCol -= 1 }; pendingWrap = false; capture?.backspace()
        case 0x09: tab()
        case 0x0A, 0x0B, 0x0C:
            lineFeed()
            if newlineMode { cursorCol = 0 }
            capture?.newline()
        case 0x0D: cursorCol = 0; pendingWrap = false; capture?.carriageReturn()
        case 0x0E: shifted = true
        case 0x0F: shifted = false
        case 0x20...0x7E: put(UInt32(b))
        case 0xC2...0xDF: utf8Pending = [b]; utf8Needed = 1
        case 0xE0...0xEF: utf8Pending = [b]; utf8Needed = 2
        case 0xF0...0xF4: utf8Pending = [b]; utf8Needed = 3
        default: break
        }
    }

    private static let lineDrawing: [UInt8: UInt32] = [
        0x6A: 0x2518, 0x6B: 0x2510, 0x6C: 0x250C, 0x6D: 0x2514, 0x6E: 0x253C, 0x71: 0x2500, 0x74: 0x251C,
        0x75: 0x2524, 0x76: 0x2534, 0x77: 0x252C, 0x78: 0x2502, 0x61: 0x2592, 0x60: 0x25C6, 0x7E: 0x00B7,
        0x6F: 0x2500, 0x70: 0x2500, 0x72: 0x2500, 0x73: 0x2500, 0x66: 0x00B0, 0x67: 0x00B1,
    ]

    private func put(_ scalar: UInt32) {
        var scalar = scalar
        if scalar < 0x80, (shifted ? g1Graphics : g0Graphics), let mapped = Self.lineDrawing[UInt8(scalar)] { scalar = mapped }
        let w = CharacterWidth.of(scalar)
        guard w > 0 else { return }
        if pendingWrap && autowrap { wrapToNextLine() }
        pendingWrap = false
        if w == 2 && cursorCol == cols - 1 {
            guard autowrap else { return }
            wrapToNextLine()
        }
        if insertMode {
            for _ in 0..<w { screen[cursorRow].insert(erased(), at: cursorCol); screen[cursorRow].removeLast() }
        }
        clearWideOverlap(row: cursorRow, col: cursorCol)
        if w == 2 { clearWideOverlap(row: cursorRow, col: cursorCol + 1) }
        var cell = pen
        cell.scalar = scalar
        cell.width = UInt8(w)
        screen[cursorRow][cursorCol] = cell
        if w == 2, cursorCol + 1 < cols {
            var tail = pen
            tail.scalar = 0x20; tail.width = 0
            screen[cursorRow][cursorCol + 1] = tail
        }
        if !isAlternateScreen { capture?.write(Character(Unicode.Scalar(scalar) ?? " ")) }
        cursorCol += w
        if cursorCol >= cols { cursorCol = cols - 1; pendingWrap = true }
    }

    private func wrapToNextLine() {
        cursorCol = 0
        lineFeed()
        capture?.newline()
    }

    private func clearWideOverlap(row: Int, col: Int) {
        guard col < cols else { return }
        if screen[row][col].width == 0, col > 0 { screen[row][col - 1] = erased() }
        if screen[row][col].width == 2, col + 1 < cols { screen[row][col + 1] = erased() }
    }

    private func tab() {
        var c = cursorCol + 1
        while c < cols - 1 && !tabStops.contains(c) { c += 1 }
        cursorCol = min(c, cols - 1)
        pendingWrap = false
    }

    // MARK: Scrolling

    private func erased() -> TermCell { var c = TermCell(); c.bg = pen.bg; return c }
    private func blankLine() -> [TermCell] { Array(repeating: erased(), count: cols) }

    private func lineFeed() {
        pendingWrap = false
        if cursorRow == scrollBottom { scrollUp(1) }
        else if cursorRow < rows - 1 { cursorRow += 1 }
    }

    private func reverseIndex() {
        pendingWrap = false
        if cursorRow == scrollTop { scrollDown(1) }
        else if cursorRow > 0 { cursorRow -= 1 }
    }

    private func scrollUp(_ n: Int) {
        for _ in 0..<max(1, min(n, scrollBottom - scrollTop + 1)) {
            let removed = screen.remove(at: scrollTop)
            if !isAlternateScreen && scrollTop == 0 && scrollBottom == rows - 1 {
                scrollback.append(removed)
                if scrollback.count > scrollbackLimit { scrollback.removeFirst(scrollback.count - scrollbackLimit) }
            }
            screen.insert(blankLine(), at: scrollBottom)
        }
    }

    private func scrollDown(_ n: Int) {
        for _ in 0..<max(1, min(n, scrollBottom - scrollTop + 1)) {
            screen.remove(at: scrollBottom)
            screen.insert(blankLine(), at: scrollTop)
        }
    }

    // MARK: Escape

    private func escape(_ b: UInt8) {
        state = .ground
        switch b {
        case UInt8(ascii: "["): state = .csi; csiBytes = []
        case UInt8(ascii: "]"): state = .osc; oscBytes = []
        case UInt8(ascii: "P"), UInt8(ascii: "X"), UInt8(ascii: "^"), UInt8(ascii: "_"): state = .ignoreString
        case UInt8(ascii: "("): state = .escapeIntermediate; pendingCharset = 0
        case UInt8(ascii: ")"): state = .escapeIntermediate; pendingCharset = 1
        case UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "#"), UInt8(ascii: " "): state = .escapeIntermediate; pendingCharset = -1
        case UInt8(ascii: "7"): saveCursor()
        case UInt8(ascii: "8"): restoreCursor()
        case UInt8(ascii: "D"): lineFeed()
        case UInt8(ascii: "E"): cursorCol = 0; lineFeed()
        case UInt8(ascii: "M"): reverseIndex()
        case UInt8(ascii: "H"): tabStops.insert(cursorCol)
        case UInt8(ascii: "c"): fullReset()
        case 0x1B: state = .escape
        default: break   // = > \ and unknown
        }
    }

    private var pendingCharset = -1

    private func saveCursor() { savedCursor = (cursorRow, cursorCol, pen, originMode) }
    private func restoreCursor() {
        cursorRow = min(savedCursor.row, rows - 1); cursorCol = min(savedCursor.col, cols - 1)
        pen = savedCursor.pen; originMode = savedCursor.origin; pendingWrap = false
    }

    private func fullReset() {
        pen = TermCell(); scrollTop = 0; scrollBottom = rows - 1
        cursorRow = 0; cursorCol = 0; pendingWrap = false
        autowrap = true; originMode = false; insertMode = false; newlineMode = false
        cursorVisible = true; applicationCursorKeys = false; bracketedPaste = false
        g0Graphics = false; g1Graphics = false; shifted = false
        screen = (0..<rows).map { _ in blankLine() }
        resetTabs()
    }

    private func resetTabs() { tabStops = Set(stride(from: 8, to: max(cols, 9), by: 8)) }

    // MARK: CSI

    private func csi(_ b: UInt8) {
        csiBytes.append(b)
        guard (0x40...0x7E).contains(b) else {
            if csiBytes.count > 64 { state = .ground }   // runaway sequence
            return
        }
        state = .ground
        let final = b
        var body = csiBytes.dropLast()
        var priv: UInt8?
        if let first = body.first, (0x3C...0x3F).contains(first) { priv = first; body = body.dropFirst() }
        let params: [Int] = body.filter { $0 != 0x20 }.split(separator: UInt8(ascii: ";"), omittingEmptySubsequences: false)
            .map { part in Int(String(decoding: part.filter { $0 >= 0x30 && $0 <= 0x39 }, as: UTF8.self)) ?? -1 }
        dispatchCSI(final: final, params: params.isEmpty ? [-1] : params, priv: priv)
    }

    private func p(_ params: [Int], _ i: Int, _ def: Int) -> Int {
        guard i < params.count, params[i] > 0 else { return def }
        return params[i]
    }

    private func dispatchCSI(final: UInt8, params: [Int], priv: UInt8?) {
        let n = p(params, 0, 1)
        switch (priv, final) {
        case (nil, UInt8(ascii: "A")): moveCursor(row: cursorRow - n, col: cursorCol, clampToRegion: true)
        case (nil, UInt8(ascii: "B")), (nil, UInt8(ascii: "e")): moveCursor(row: cursorRow + n, col: cursorCol, clampToRegion: true)
        case (nil, UInt8(ascii: "C")), (nil, UInt8(ascii: "a")): moveCursor(row: cursorRow, col: cursorCol + n)
        case (nil, UInt8(ascii: "D")): moveCursor(row: cursorRow, col: cursorCol - n)
        case (nil, UInt8(ascii: "E")): moveCursor(row: cursorRow + n, col: 0, clampToRegion: true)
        case (nil, UInt8(ascii: "F")): moveCursor(row: cursorRow - n, col: 0, clampToRegion: true)
        case (nil, UInt8(ascii: "G")), (nil, UInt8(ascii: "`")): moveCursor(row: cursorRow, col: n - 1)
        case (nil, UInt8(ascii: "H")), (nil, UInt8(ascii: "f")):
            let top = originMode ? scrollTop : 0
            moveCursor(row: top + p(params, 0, 1) - 1, col: p(params, 1, 1) - 1)
        case (nil, UInt8(ascii: "d")):
            moveCursor(row: (originMode ? scrollTop : 0) + n - 1, col: cursorCol)
        case (nil, UInt8(ascii: "J")): eraseDisplay(params.first ?? 0)
        case (nil, UInt8(ascii: "K")): eraseLine(params.first ?? 0)
        case (nil, UInt8(ascii: "L")): insertLines(n)
        case (nil, UInt8(ascii: "M")): deleteLines(n)
        case (nil, UInt8(ascii: "@")): insertChars(n)
        case (nil, UInt8(ascii: "P")): deleteChars(n)
        case (nil, UInt8(ascii: "X")): eraseChars(n)
        case (nil, UInt8(ascii: "S")): scrollUp(n)
        case (nil, UInt8(ascii: "T")): scrollDown(n)
        case (nil, UInt8(ascii: "m")): sgr(params)
        case (nil, UInt8(ascii: "r")): setScrollRegion(top: p(params, 0, 1), bottom: p(params, 1, rows))
        case (nil, UInt8(ascii: "s")): saveCursor()
        case (nil, UInt8(ascii: "u")): restoreCursor()
        case (nil, UInt8(ascii: "g")):
            if (params.first ?? 0) == 3 { tabStops.removeAll() } else { tabStops.remove(cursorCol) }
        case (nil, UInt8(ascii: "n")): deviceStatus(params.first ?? 0)
        case (nil, UInt8(ascii: "c")): respond("\u{1B}[?1;2c")
        case (UInt8(ascii: ">"), UInt8(ascii: "c")): respond("\u{1B}[>0;0;0c")
        case (nil, UInt8(ascii: "h")): setModes(params, on: true, private: false)
        case (nil, UInt8(ascii: "l")): setModes(params, on: false, private: false)
        case (UInt8(ascii: "?"), UInt8(ascii: "h")): setModes(params, on: true, private: true)
        case (UInt8(ascii: "?"), UInt8(ascii: "l")): setModes(params, on: false, private: true)
        default: break
        }
    }

    private func moveCursor(row: Int, col: Int, clampToRegion: Bool = false) {
        let minRow = originMode ? scrollTop : 0, maxRow = originMode ? scrollBottom : rows - 1
        cursorRow = max(minRow, min(maxRow, row))
        cursorCol = max(0, min(cols - 1, col))
        pendingWrap = false
    }

    private func deviceStatus(_ kind: Int) {
        switch kind {
        case 5: respond("\u{1B}[0n")
        case 6:
            let r = cursorRow - (originMode ? scrollTop : 0) + 1
            respond("\u{1B}[\(r);\(cursorCol + 1)R")
        default: break
        }
    }

    private func respond(_ s: String) { onResponse?(Array(s.utf8)) }

    private func setScrollRegion(top: Int, bottom: Int) {
        let t = max(1, min(top, rows)), bt = max(1, min(bottom, rows))
        guard t < bt else { return }
        scrollTop = t - 1; scrollBottom = bt - 1
        cursorRow = originMode ? scrollTop : 0; cursorCol = 0; pendingWrap = false
    }

    private func setModes(_ params: [Int], on: Bool, private priv: Bool) {
        for mode in params where mode > 0 {
            if priv {
                switch mode {
                case 1: applicationCursorKeys = on
                case 6: originMode = on; cursorRow = on ? scrollTop : 0; cursorCol = 0
                case 7: autowrap = on
                case 25: cursorVisible = on
                case 47, 1047, 1049: setAlternateScreen(on, saveCursor: mode == 1049)
                case 2004: bracketedPaste = on
                default: break
                }
            } else {
                switch mode {
                case 4: insertMode = on
                case 20: newlineMode = on
                default: break
                }
            }
        }
    }

    private func setAlternateScreen(_ on: Bool, saveCursor save: Bool) {
        guard on != isAlternateScreen else { return }
        if on {
            savedPrimary = screen
            savedPrimaryCursor = (cursorRow, cursorCol)
            isAlternateScreen = true
            screen = (0..<rows).map { _ in blankLine() }
            if save { cursorRow = 0; cursorCol = 0 }
            capture = nil
        } else {
            isAlternateScreen = false
            if let saved = savedPrimary { screen = saved }
            if let c = savedPrimaryCursor { cursorRow = min(c.row, rows - 1); cursorCol = min(c.col, cols - 1) }
            savedPrimary = nil; savedPrimaryCursor = nil
        }
        pendingWrap = false
    }

    // MARK: Erase / insert / delete

    private func eraseDisplay(_ mode: Int) {
        switch mode {
        case 1:
            for r in 0..<cursorRow { screen[r] = blankLine() }
            for c in 0...cursorCol { screen[cursorRow][c] = erased() }
        case 2:
            for r in 0..<rows { screen[r] = blankLine() }
        case 3:
            scrollback.removeAll()
        default:
            for c in cursorCol..<cols { screen[cursorRow][c] = erased() }
            if cursorRow + 1 < rows { for r in (cursorRow + 1)..<rows { screen[r] = blankLine() } }
        }
    }

    private func eraseLine(_ mode: Int) {
        switch mode {
        case 1: for c in 0...cursorCol { screen[cursorRow][c] = erased() }
        case 2: screen[cursorRow] = blankLine()
        default: for c in cursorCol..<cols { screen[cursorRow][c] = erased() }
        }
    }

    private func insertLines(_ n: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        for _ in 0..<min(n, scrollBottom - cursorRow + 1) {
            screen.remove(at: scrollBottom)
            screen.insert(blankLine(), at: cursorRow)
        }
        cursorCol = 0
    }

    private func deleteLines(_ n: Int) {
        guard cursorRow >= scrollTop, cursorRow <= scrollBottom else { return }
        for _ in 0..<min(n, scrollBottom - cursorRow + 1) {
            screen.remove(at: cursorRow)
            screen.insert(blankLine(), at: scrollBottom)
        }
        cursorCol = 0
    }

    private func insertChars(_ n: Int) {
        for _ in 0..<min(n, cols - cursorCol) { screen[cursorRow].insert(erased(), at: cursorCol); screen[cursorRow].removeLast() }
    }

    private func deleteChars(_ n: Int) {
        for _ in 0..<min(n, cols - cursorCol) { screen[cursorRow].remove(at: cursorCol); screen[cursorRow].append(erased()) }
    }

    private func eraseChars(_ n: Int) {
        for c in cursorCol..<min(cols, cursorCol + n) { screen[cursorRow][c] = erased() }
    }

    // MARK: SGR

    private func sgr(_ params: [Int]) {
        var i = 0
        let list = params.map { $0 < 0 ? 0 : $0 }
        while i < list.count {
            let v = list[i]
            switch v {
            case 0: pen = TermCell()
            case 1: pen.attrs.insert(.bold)
            case 2: pen.attrs.insert(.dim)
            case 3: pen.attrs.insert(.italic)
            case 4: pen.attrs.insert(.underline)
            case 7: pen.attrs.insert(.inverse)
            case 8: pen.attrs.insert(.hidden)
            case 9: pen.attrs.insert(.strike)
            case 22: pen.attrs.subtract([.bold, .dim])
            case 23: pen.attrs.remove(.italic)
            case 24: pen.attrs.remove(.underline)
            case 27: pen.attrs.remove(.inverse)
            case 28: pen.attrs.remove(.hidden)
            case 29: pen.attrs.remove(.strike)
            case 30...37: pen.fg = .indexed(v - 30)
            case 39: pen.fg = .default
            case 40...47: pen.bg = .indexed(v - 40)
            case 49: pen.bg = .default
            case 90...97: pen.fg = .indexed(v - 90 + 8)
            case 100...107: pen.bg = .indexed(v - 100 + 8)
            case 38, 48:
                var color: TermColor?
                if i + 1 < list.count, list[i + 1] == 5, i + 2 < list.count {
                    color = .indexed(list[i + 2]); i += 2
                } else if i + 1 < list.count, list[i + 1] == 2, i + 4 < list.count {
                    color = .rgb(list[i + 2], list[i + 3], list[i + 4]); i += 4
                }
                if let color { if v == 38 { pen.fg = color } else { pen.bg = color } }
            default: break
            }
            i += 1
        }
    }

    // MARK: OSC

    private func osc(_ b: UInt8) {
        switch b {
        case 0x07: dispatchOSC(); state = .ground
        case 0x1B: dispatchOSC(); state = .escape
        default: if oscBytes.count < 4096 { oscBytes.append(b) }
        }
    }

    private func dispatchOSC() {
        let text = String(decoding: oscBytes, as: UTF8.self)
        oscBytes = []
        let parts = text.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard let code = parts.first else { return }
        let rest = parts.count > 1 ? String(parts[1]) : ""
        switch code {
        case "0", "2": onEvent?(.title(rest))
        case "7":
            // file://host/path. Shells rarely percent-encode, so parse by hand and decode leniently.
            guard rest.hasPrefix("file://") else { break }
            let afterScheme = rest.dropFirst("file://".count)
            guard let slash = afterScheme.firstIndex(of: "/") else { break }
            let raw = String(afterScheme[slash...])
            onEvent?(.cwd(raw.removingPercentEncoding ?? raw))
        case "133":
            let sub = rest.split(separator: ";", omittingEmptySubsequences: false)
            switch sub.first {
            case "A": onEvent?(.promptStart)
            case "C":
                capture = isAlternateScreen ? nil : CaptureLog()
                isCapturing = capture != nil
                onEvent?(.commandStart)
            case "D":
                let code = sub.count > 1 ? Int(sub[1]) : nil
                if let capture { lastOutput = capture.text }
                capture = nil; isCapturing = false
                onEvent?(.commandEnd(code))
            default: break
            }
        case "7777": onEvent?(.commandText(rest))
        default: break
        }
    }

    // MARK: Resize

    public func resize(cols newCols: Int, rows newRows: Int) {
        let newCols = max(1, newCols), newRows = max(1, newRows)
        guard newCols != cols || newRows != rows else { return }
        func fit(_ line: [TermCell]) -> [TermCell] {
            if line.count >= newCols { return Array(line.prefix(newCols)) }
            return line + Array(repeating: TermCell(), count: newCols - line.count)
        }
        screen = screen.map(fit)
        scrollback = scrollback.map(fit)
        if newRows < rows {
            // Lines that no longer fit scroll into history, keeping the cursor line on screen.
            var drop = rows - newRows
            while drop > 0 && screen.count > newRows {
                if cursorRow > 0 {
                    let removed = screen.removeFirst()
                    if !isAlternateScreen { scrollback.append(removed) }
                    cursorRow -= 1
                } else { screen.removeLast() }
                drop -= 1
            }
        } else if newRows > rows {
            screen += (0..<(newRows - rows)).map { _ in Array(repeating: TermCell(), count: newCols) }
        }
        if let saved = savedPrimary { savedPrimary = Array(saved.map(fit).prefix(newRows)) }
        cols = newCols; rows = newRows
        scrollTop = 0; scrollBottom = rows - 1
        cursorRow = min(cursorRow, rows - 1); cursorCol = min(cursorCol, cols - 1)
        pendingWrap = false
        resetTabs()
        version &+= 1
    }

    /// Clears the screen and history (like Cmd+K).
    public func clearAll() {
        scrollback.removeAll()
        for r in 0..<rows { screen[r] = blankLine() }
        cursorRow = 0; cursorCol = 0; pendingWrap = false
        version &+= 1
    }
}
