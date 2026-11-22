import Foundation
import Testing
@testable import MiniTerminalCore

private func s(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

@Suite struct KeyEncoderTests {
    @Test func plainCharactersAndControlKeys() {
        #expect(KeyEncoder.encode(.character("a")) == [0x61])
        #expect(s(KeyEncoder.encode(.character("é"))) == "é")
        #expect(KeyEncoder.encode(.character("c"), modifiers: .control) == [0x03])        // Ctrl-C
        #expect(KeyEncoder.encode(.character("d"), modifiers: .control) == [0x04])
        #expect(KeyEncoder.encode(.character("Z"), modifiers: .control) == [0x1A])
        #expect(KeyEncoder.encode(.character("["), modifiers: .control) == [0x1B])
        #expect(KeyEncoder.encode(.character(" "), modifiers: .control) == [0x00])
        #expect(KeyEncoder.encode(.character("?"), modifiers: .control) == [0x7F])
    }

    @Test func optionIsMetaAndCommandIsLeftToTheApp() {
        #expect(KeyEncoder.encode(.character("f"), modifiers: .option) == [0x1B, 0x66])
        #expect(KeyEncoder.encode(.character("c"), modifiers: .command).isEmpty)
    }

    @Test func editingKeys() {
        #expect(KeyEncoder.encode(.enter) == [0x0D])
        #expect(KeyEncoder.encode(.tab) == [0x09])
        #expect(s(KeyEncoder.encode(.backTab)) == "\u{1B}[Z")
        #expect(KeyEncoder.encode(.escape) == [0x1B])
        #expect(KeyEncoder.encode(.backspace) == [0x7F])
        #expect(KeyEncoder.encode(.backspace, modifiers: .option) == [0x1B, 0x7F])      // delete a word
        #expect(KeyEncoder.encode(.backspace, modifiers: .command) == [0x15])           // delete to line start
        #expect(s(KeyEncoder.encode(.forwardDelete)) == "\u{1B}[3~")
    }

    @Test func arrowsNormalAndApplicationMode() {
        #expect(s(KeyEncoder.encode(.up)) == "\u{1B}[A")
        #expect(s(KeyEncoder.encode(.down, applicationCursor: true)) == "\u{1B}OB")
        #expect(s(KeyEncoder.encode(.right, modifiers: .shift)) == "\u{1B}[1;2C")
        #expect(s(KeyEncoder.encode(.left, modifiers: .control)) == "\u{1B}[1;5D")
        #expect(s(KeyEncoder.encode(.up, modifiers: [.shift, .control], applicationCursor: true)) == "\u{1B}[1;6A")
    }

    @Test func macWordAndLineNavigation() {
        #expect(s(KeyEncoder.encode(.left, modifiers: .option)) == "\u{1B}b")
        #expect(s(KeyEncoder.encode(.right, modifiers: .option)) == "\u{1B}f")
        #expect(KeyEncoder.encode(.left, modifiers: .command) == [0x01])
        #expect(KeyEncoder.encode(.right, modifiers: .command) == [0x05])
    }

    @Test func homeEndPagingAndFunctionKeys() {
        #expect(s(KeyEncoder.encode(.home)) == "\u{1B}[H")
        #expect(s(KeyEncoder.encode(.end, applicationCursor: true)) == "\u{1B}OF")
        #expect(s(KeyEncoder.encode(.pageUp)) == "\u{1B}[5~")
        #expect(s(KeyEncoder.encode(.pageDown, modifiers: .shift)) == "\u{1B}[6;2~")
        #expect(s(KeyEncoder.encode(.function(1))) == "\u{1B}OP")
        #expect(s(KeyEncoder.encode(.function(5))) == "\u{1B}[15~")
        #expect(s(KeyEncoder.encode(.function(12), modifiers: .control)) == "\u{1B}[24;5~")
        #expect(KeyEncoder.encode(.function(40)).isEmpty)
    }

    @Test func pasteConvertsNewlinesAndBrackets() {
        #expect(s(KeyEncoder.paste("a\nb\r\nc", bracketed: false)) == "a\rb\rc")
        #expect(s(KeyEncoder.paste("ls", bracketed: true)) == "\u{1B}[200~ls\u{1B}[201~")
    }

    @Test func bracketedPasteCannotBeEndedEarlyByThePastedText() {
        let hostile = "echo hi\u{1B}[201~\nrm -rf ~"
        let out = s(KeyEncoder.paste(hostile, bracketed: true))
        #expect(out.hasPrefix("\u{1B}[200~") && out.hasSuffix("\u{1B}[201~"))
        let inner = out.dropFirst("\u{1B}[200~".count).dropLast("\u{1B}[201~".count)
        #expect(!inner.contains("\u{1B}"))                 // no escape survives inside the paste
    }

    @Test func shellQuoting() {
        #expect(ShellQuote.quote("/Users/me/file.txt") == "/Users/me/file.txt")
        #expect(ShellQuote.quote("/Users/me/My Files/a b.txt") == "'/Users/me/My Files/a b.txt'")
        #expect(ShellQuote.quote("it's") == "'it'\\''s'")
        #expect(ShellQuote.quote("") == "''")
        #expect(ShellQuote.quote("a;rm -rf") == "'a;rm -rf'")
        #expect(ShellQuote.quote("$(whoami)") == "'$(whoami)'")
    }
}

@Suite struct HistoryTests {
    private func t(_ n: Int) -> Date { Date(timeIntervalSince1970: Double(n)) }

    @Test func recordsNewestFirstAndMergesRepeats() {
        var h = CommandHistory()
        h.record(command: "ls", cwd: "/a", exitCode: 0, duration: 0.1, at: t(1))
        h.record(command: "git status", cwd: "/a", exitCode: 0, duration: 0.2, at: t(2))
        h.record(command: "ls", cwd: "/b", exitCode: 1, duration: 0.3, at: t(3))
        #expect(h.entries.map(\.command) == ["ls", "git status"])
        #expect(h.entries[0].runs == 2 && h.entries[0].exitCode == 1 && h.entries[0].cwd == "/b")
    }

    @Test func neverStoresSecretsOrSpacePrefixedLines() {
        var h = CommandHistory()
        for bad in ["export API_KEY=abc123", "curl -H 'Authorization: Bearer xyz' https://a.b", "mysql --password=hunter2",
                    "login password=foo", "TOKEN=abc ./run", "echo ghp_abcdefghijklmnopqrstuvwxyz0123", "aws s3 ls AKIAABCDEFGHIJKLMNOP",
                    " ls -la", "   ", ""] {
            let stored = h.record(command: bad, cwd: nil, exitCode: 0, duration: 0)
            #expect(!stored, "\(bad)")
        }
        #expect(h.entries.isEmpty)
        #expect(CommandHistory.shouldRecord("npm run build"))
        #expect(CommandHistory.shouldRecord("ls ~/Passwords"))                                  // a word without = or : is fine
        #expect(CommandHistory.shouldRecord("git commit -m 'update the password reset page'"))   // prose that only mentions one
    }

    @Test func pinnedEntriesSurviveTrimmingAndKeepTheirPin() {
        var h = CommandHistory()
        h.record(command: "keep me", cwd: nil, exitCode: 0, duration: 0, at: t(0))
        h.togglePin(h.entries[0].id)
        for i in 0..<(CommandHistory.limit + 20) { h.record(command: "cmd \(i)", cwd: nil, exitCode: 0, duration: 0, at: t(i + 1)) }
        #expect(h.entries.count == CommandHistory.limit + 1)
        #expect(h.pinned.map(\.command) == ["keep me"])
        h.record(command: "keep me", cwd: nil, exitCode: 0, duration: 0, at: t(9999))     // re-running keeps the pin
        #expect(h.entries[0].pinned && h.entries[0].runs == 2)
        h.clearUnpinned()
        #expect(h.entries.map(\.command) == ["keep me"])
    }

    @Test func removeAndTogglePin() {
        var h = CommandHistory()
        h.record(command: "a", cwd: nil, exitCode: 0, duration: 0)
        let id = h.entries[0].id
        h.togglePin(id); #expect(h.entries[0].pinned)
        h.togglePin(id); #expect(!h.entries[0].pinned)
        h.remove(id); #expect(h.entries.isEmpty)
    }

    @Test func searchMatchesAllWordsAnyOrderAndRanksPrefixes() {
        var h = CommandHistory()
        for (i, c) in ["docker compose up", "git log --oneline", "echo git", "git status", "npm run dev"].enumerated() {
            h.record(command: c, cwd: nil, exitCode: 0, duration: 0, at: t(i))
        }
        #expect(h.search("").count == 5)
        #expect(Set(h.search("git").map(\.command)) == ["git log --oneline", "echo git", "git status"])
        #expect(h.search("git").first?.command == "git status")                    // prefix match, newest first
        #expect(h.search("ONELINE git").map(\.command) == ["git log --oneline"])    // any order, any case
        #expect(h.search("nonexistent").isEmpty)
    }

    @Test func frequentCommandsRankByRunCount() {
        var h = CommandHistory()
        for _ in 0..<3 { h.record(command: "make", cwd: nil, exitCode: 0, duration: 0) }
        for _ in 0..<2 { h.record(command: "ls", cwd: nil, exitCode: 0, duration: 0) }
        h.record(command: "pwd", cwd: nil, exitCode: 0, duration: 0)
        #expect(h.frequent(limit: 2) == ["make", "ls"])
    }

    @Test func roundTripsThroughJSON() throws {
        var h = CommandHistory()
        h.record(command: "ls", cwd: "/x", exitCode: 0, duration: 1.5)
        let data = try JSONEncoder().encode(h)
        #expect(try JSONDecoder().decode(CommandHistory.self, from: data) == h)
    }
}
