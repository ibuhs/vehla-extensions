import Foundation
import Testing
@testable import MiniTerminalCore

private func term(_ cols: Int = 20, _ rows: Int = 5) -> TerminalEmulator { TerminalEmulator(cols: cols, rows: rows) }
private func screen(_ t: TerminalEmulator) -> [String] { (0..<t.rows).map { t.text(row: $0) } }

@Suite struct TextTests {
    @Test func printsAndAdvances() {
        let t = term()
        t.feed("hello")
        #expect(t.text(row: 0) == "hello")
        #expect(t.cursorCol == 5 && t.cursorRow == 0)
    }

    @Test func carriageReturnAndLineFeed() {
        let t = term()
        t.feed("one\r\ntwo\rXY")
        #expect(screen(t)[0] == "one")
        #expect(screen(t)[1] == "XYo")        // CR returns to column 0, then overwrites
    }

    @Test func wrapsAtTheRightEdgeAndScrolls() {
        let t = term(5, 3)
        t.feed("abcdefghij")                  // exactly two lines
        #expect(screen(t) == ["abcde", "fghij", ""])
        t.feed("klmno\r\npq")
        #expect(screen(t) == ["fghij", "klmno", "pq"])
        #expect(t.scrollback.count == 1)
        #expect(String(t.scrollback[0].map { $0.character }) == "abcde")
    }

    @Test func pendingWrapDoesNotWrapUntilTheNextCharacter() {
        let t = term(5, 3)
        t.feed("abcde")
        #expect(t.cursorRow == 0)             // still on the first line, wrap is pending
        t.feed("\r\nx")
        #expect(screen(t)[1] == "x")          // a CR/LF after a full line must not double-space
    }

    @Test func backspaceAndTab() {
        let t = term()
        t.feed("ab\u{8}c")
        #expect(t.text(row: 0) == "ac")
        t.feed("\r\tX")
        #expect(t.cursorCol == 9 && t.cell(row: 0, col: 8).character == "X")
    }

    @Test func decodesUTF8AcrossChunkBoundaries() {
        let t = term()
        let bytes = Array("é€😀".utf8)
        for b in bytes { t.feed([b]) }        // one byte at a time
        #expect(t.text(row: 0) == "é€😀")
    }

    @Test func wideCharactersTakeTwoCells() {
        let t = term(6, 2)
        t.feed("日本a")
        #expect(t.cell(row: 0, col: 0).width == 2 && t.cell(row: 0, col: 1).width == 0)
        #expect(t.cell(row: 0, col: 4).character == "a")
        #expect(t.cursorCol == 5)
        t.feed("\r\n12345日")                  // a wide char that doesn't fit wraps (and here scrolls) instead of splitting
        #expect(t.text(row: 0) == "12345")
        #expect(t.text(row: 1) == "日")
        #expect(t.cell(row: 1, col: 0).width == 2)
    }

    @Test func invalidUTF8BecomesAReplacementCharacter() {
        let t = term()
        t.feed([0xC3, 0x41])                  // a lead byte followed by plain ASCII
        #expect(t.text(row: 0).hasPrefix("\u{FFFD}"))
    }

    @Test func lineDrawingCharacterSet() {
        let t = term()
        t.feed("\u{1B}(0lqk\u{1B}(Bq")
        #expect(t.text(row: 0) == "┌─┐q")
    }
}

@Suite struct CursorTests {
    @Test func absoluteAndRelativeMovement() {
        let t = term(10, 6)
        t.feed("\u{1B}[3;5H")
        #expect(t.cursorRow == 2 && t.cursorCol == 4)
        t.feed("\u{1B}[2A\u{1B}[3C")
        #expect(t.cursorRow == 0 && t.cursorCol == 7)
        t.feed("\u{1B}[99B\u{1B}[99D")
        #expect(t.cursorRow == 5 && t.cursorCol == 0)
        t.feed("\u{1B}[H")
        #expect(t.cursorRow == 0 && t.cursorCol == 0)
        t.feed("\u{1B}[4G\u{1B}[3d")
        #expect(t.cursorCol == 3 && t.cursorRow == 2)
    }

    @Test func saveAndRestore() {
        let t = term()
        t.feed("\u{1B}[2;3H\u{1B}7\u{1B}[H\u{1B}8")
        #expect(t.cursorRow == 1 && t.cursorCol == 2)
    }

    @Test func reverseIndexScrollsDownAtTheTop() {
        let t = term(5, 3)
        t.feed("a\r\nb\r\nc\u{1B}[H\u{1B}M")
        #expect(screen(t) == ["", "a", "b"])
    }

    @Test func cursorVisibilityAndModes() {
        let t = term()
        #expect(t.cursorVisible)
        t.feed("\u{1B}[?25l")
        #expect(!t.cursorVisible)
        t.feed("\u{1B}[?25h\u{1B}[?1h\u{1B}[?2004h")
        #expect(t.cursorVisible && t.applicationCursorKeys && t.bracketedPaste)
        t.feed("\u{1B}[?1l\u{1B}[?2004l")
        #expect(!t.applicationCursorKeys && !t.bracketedPaste)
    }
}

@Suite struct EditingTests {
    @Test func eraseInLine() {
        let t = term(10, 2)
        t.feed("0123456789\u{1B}[1;5H\u{1B}[K")
        #expect(t.text(row: 0) == "0123")
        t.feed("\u{1B}[1;1H0123456789\u{1B}[1;5H\u{1B}[1K")
        #expect(t.text(row: 0) == "     56789")
        #expect(t.cell(row: 0, col: 3).character == " " && t.cell(row: 0, col: 5).character == "5")
        t.feed("\u{1B}[2K")
        #expect(t.text(row: 0) == "")
    }

    @Test func eraseInDisplay() {
        let t = term(5, 3)
        t.feed("aaaaa\r\nbbbbb\r\nccccc\u{1B}[2;3H\u{1B}[J")
        #expect(screen(t) == ["aaaaa", "bb", ""])
        t.feed("\u{1B}[2J")
        #expect(screen(t) == ["", "", ""])
    }

    @Test func insertAndDeleteCharacters() {
        let t = term(8, 2)
        t.feed("abcdef\u{1B}[1;3H\u{1B}[2@")
        #expect(t.text(row: 0) == "ab  cdef")
        t.feed("\u{1B}[3P")
        #expect(t.text(row: 0) == "abdef")
        t.feed("\u{1B}[2X")
        #expect(t.text(row: 0) == "ab  f")
    }

    @Test func insertAndDeleteLines() {
        let t = term(4, 4)
        t.feed("a\r\nb\r\nc\r\nd\u{1B}[2;1H\u{1B}[L")
        #expect(screen(t) == ["a", "", "b", "c"])
        t.feed("\u{1B}[2M")
        #expect(screen(t) == ["a", "c", "", ""])
    }

    @Test func scrollRegionKeepsTheRestInPlace() {
        let t = term(4, 5)
        t.feed("h\r\n1\r\n2\r\n3\r\nf")
        t.feed("\u{1B}[2;4r")                  // rows 2-4 scroll
        t.feed("\u{1B}[4;1H\r\nX")             // LF at the bottom of the region scrolls only the region
        #expect(screen(t) == ["h", "2", "3", "X", "f"])
        #expect(t.scrollback.isEmpty)           // a partial region never feeds scrollback
    }

    @Test func explicitScrollUpAndDown() {
        let t = term(3, 3)
        t.feed("a\r\nb\r\nc\u{1B}[S")
        #expect(screen(t) == ["b", "c", ""])
        t.feed("\u{1B}[T")
        #expect(screen(t) == ["", "b", "c"])
    }
}

@Suite struct StyleTests {
    @Test func basicAndBrightColours() {
        let t = term()
        t.feed("\u{1B}[31mR\u{1B}[92mG\u{1B}[44mB\u{1B}[0mN")
        #expect(t.cell(row: 0, col: 0).fg == .indexed(1))
        #expect(t.cell(row: 0, col: 1).fg == .indexed(10))
        #expect(t.cell(row: 0, col: 2).bg == .indexed(4))
        #expect(t.cell(row: 0, col: 3).fg == .default && t.cell(row: 0, col: 3).bg == .default)
    }

    @Test func extendedColours() {
        let t = term()
        t.feed("\u{1B}[38;5;208mA\u{1B}[48;2;10;20;30mB")
        #expect(t.cell(row: 0, col: 0).fg == .indexed(208))
        #expect(t.cell(row: 0, col: 1).bg == .rgb(10, 20, 30))
        #expect(t.cell(row: 0, col: 1).fg == .indexed(208))   // the foreground persists
    }

    @Test func attributes() {
        let t = term()
        t.feed("\u{1B}[1;3;4;7;9mx\u{1B}[22;23;24;27;29my")
        #expect(t.cell(row: 0, col: 0).attrs == [.bold, .italic, .underline, .inverse, .strike])
        #expect(t.cell(row: 0, col: 1).attrs.isEmpty)
    }

    @Test func erasedCellsKeepTheBackgroundColour() {
        let t = term(6, 2)
        t.feed("\u{1B}[41m\u{1B}[2K")
        #expect(t.cell(row: 0, col: 3).bg == .indexed(1))
    }
}

@Suite struct AlternateScreenTests {
    @Test func enteringAndLeavingRestoresTheShell() {
        let t = term(10, 3)
        t.feed("prompt$ ls\r\nfile")
        t.feed("\u{1B}[?1049h")
        #expect(t.isAlternateScreen && screen(t) == ["", "", ""])
        t.feed("vim!")
        #expect(t.text(row: 0) == "vim!")
        t.feed("\u{1B}[?1049l")
        #expect(!t.isAlternateScreen)
        #expect(t.text(row: 0) == "prompt$ ls" && t.text(row: 1) == "file")
        #expect(t.cursorRow == 1 && t.cursorCol == 4)
    }

    @Test func nothingScrollsIntoHistoryOnTheAlternateScreen() {
        let t = term(4, 2)
        t.feed("\u{1B}[?1049h1\r\n2\r\n3\r\n4")
        #expect(t.scrollbackCount == 0)
        t.feed("\u{1B}[?1049l")
        #expect(t.scrollback.isEmpty)
    }
}

@Suite struct ResponseTests {
    @Test func cursorPositionReport() {
        let t = term(20, 10)
        var sent: [UInt8] = []
        t.onResponse = { sent += $0 }
        t.feed("\u{1B}[4;7H\u{1B}[6n")
        #expect(String(decoding: sent, as: UTF8.self) == "\u{1B}[4;7R")
    }

    @Test func deviceAttributesAndStatus() {
        let t = term()
        var sent = ""
        t.onResponse = { sent += String(decoding: $0, as: UTF8.self) }
        t.feed("\u{1B}[c\u{1B}[5n")
        #expect(sent == "\u{1B}[?1;2c\u{1B}[0n")
    }

    @Test func doesNotEchoArbitraryQueries() {
        let t = term()
        var sent: [UInt8] = []
        t.onResponse = { sent += $0 }
        t.feed("\u{1B}[21t\u{1B}]0;evil\u{7}\u{1B}[>q")   // title report and friends are never answered
        #expect(sent.isEmpty)
    }
}

@Suite struct ShellIntegrationTests {
    private func events(_ input: String) -> (TerminalEmulator, [TerminalEvent]) {
        let t = term(30, 5)
        var seen: [TerminalEvent] = []
        t.onEvent = { seen.append($0) }
        t.feed(input)
        return (t, seen)
    }

    @Test func parsesTheMarks() {
        let (_, seen) = events("\u{1B}]7;file://host/Users/me/My%20Code\u{7}\u{1B}]133;A\u{7}\u{1B}]7777;git status\u{7}\u{1B}]133;C\u{7}out\r\n\u{1B}]133;D;0\u{7}")
        #expect(seen == [.cwd("/Users/me/My Code"), .promptStart, .commandText("git status"), .commandStart, .commandEnd(0)])
    }

    @Test func titleBellAndStringTerminator() {
        let (_, seen) = events("\u{1B}]2;My Title\u{1B}\\\u{7}")
        #expect(seen == [.title("My Title"), .bell])
    }

    @Test func commandEndWithoutAnExitStatus() {
        let (_, seen) = events("\u{1B}]133;D\u{7}")
        #expect(seen == [.commandEnd(nil)])
    }

    @Test func capturesJustThePlainOutputOfACommand() {
        let (t, _) = events("prompt$ echo hi\r\n\u{1B}]133;C\u{7}\u{1B}[31mhi\u{1B}[0m\r\nline two\r\nprogress 10%\rprogress 99%\r\n\u{1B}]133;D;0\u{7}next prompt")
        #expect(t.lastOutput == "hi\nline two\nprogress 99%")
        #expect(!t.isCapturing)
    }

    @Test func doesNotCaptureFullScreenApps() {
        let (t, _) = events("\u{1B}]133;C\u{7}before\r\n\u{1B}[?1049hsecret screen\u{1B}[?1049l\u{1B}]133;D;0\u{7}")
        #expect(!t.lastOutput.contains("secret"))
    }
}

@Suite struct ScrollbackAndResizeTests {
    @Test func scrollbackIsCappedAndAddressable() {
        let t = term(5, 2)
        t.scrollbackLimit = 3
        for i in 0..<10 { t.feed("l\(i)\r\n") }
        #expect(t.scrollback.count == 3)
        #expect(t.totalRows == 5)
        #expect(String(t.line(absolute: 0).prefix(2).map { $0.character }) == "l6")   // l0...l5 aged out
        #expect(t.line(absolute: 99).isEmpty)
    }

    @Test func extractsTextBetweenPositions() {
        let t = term(10, 3)
        t.feed("hello\r\nworld  \r\nlast")
        #expect(t.text(from: (0, 1), to: (0, 3)) == "ell")
        #expect(t.text(from: (0, 2), to: (1, 2)) == "llo\nwor")
        #expect(t.text(from: (1, 2), to: (0, 2)) == "llo\nwor")   // order doesn't matter
    }

    @Test func resizeKeepsContentAndTheCursorOnScreen() {
        let t = term(10, 4)
        t.feed("a\r\nb\r\nc\r\nd")
        t.resize(cols: 6, rows: 2)
        #expect(screen(t) == ["c", "d"])
        #expect(t.scrollback.count == 2)
        #expect(t.cursorRow == 1)
        t.resize(cols: 12, rows: 5)
        #expect(t.rows == 5 && t.cols == 12 && t.text(row: 1) == "d")
        #expect(t.cursorRow <= 4)
    }

    @Test func clearAllWipesHistory() {
        let t = term(5, 2)
        for i in 0..<5 { t.feed("l\(i)\r\n") }
        t.clearAll()
        #expect(t.scrollback.isEmpty && screen(t) == ["", ""] && t.cursorRow == 0)
    }

    @Test func fullResetClearsModes() {
        let t = term()
        t.feed("\u{1B}[?25l\u{1B}[?1h\u{1B}[31mx\u{1B}c")
        #expect(t.cursorVisible && !t.applicationCursorKeys && screen(t).allSatisfy { $0.isEmpty })
    }

    @Test func versionChangesWhenFed() {
        let t = term()
        let v = t.version
        t.feed("x")
        #expect(t.version != v)
    }
}

@Suite struct RobustnessTests {
    @Test func survivesGarbageAndHugeSequences() {
        let t = term(10, 4)
        var rng = SplitMix(seed: 42)
        for _ in 0..<200 {
            let chunk = (0..<512).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            t.feed(chunk)
        }
        t.feed("\u{1B}[" + String(repeating: "9;", count: 500) + "m")        // runaway parameters
        t.feed("\u{1B}]0;" + String(repeating: "x", count: 10_000) + "\u{7}")  // oversized OSC
        t.feed("\u{1B}[999999999999999999999Hok")
        #expect(t.cursorRow >= 0 && t.cursorRow < t.rows && t.cursorCol >= 0 && t.cursorCol < t.cols)
    }

    @Test func resizeDuringGarbageDoesNotCrash() {
        let t = term(30, 10)
        var rng = SplitMix(seed: 7)
        for i in 0..<100 {
            t.feed((0..<256).map { _ in UInt8(truncatingIfNeeded: rng.next()) })
            t.resize(cols: 3 + i % 40, rows: 1 + i % 12)
        }
        #expect(t.cursorRow < t.rows && t.cursorCol < t.cols)
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
