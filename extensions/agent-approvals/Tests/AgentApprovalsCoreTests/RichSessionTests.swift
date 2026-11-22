import Foundation
import Testing
@testable import AgentApprovalsCore

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vaa-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct ActivityTests {
    private func tool(_ name: String, _ input: [String: JSONValue]) -> HookEvent {
        HookEvent(sessionID: "s", name: "PreToolUse", toolName: name, toolInput: input)
    }

    @Test func describesTools() {
        #expect(ActivityText.describe(tool("Edit", ["file_path": .string("/a/b/CheckoutViewModel.swift")])) == "Editing CheckoutViewModel.swift")
        #expect(ActivityText.describe(tool("Read", ["file_path": .string("/a/Readme.md")])) == "Reading Readme.md")
        #expect(ActivityText.describe(tool("Bash", ["command": .string("swift build\nnext")])) == "Running swift build")
        #expect(ActivityText.describe(tool("Grep", [:])) == "Searching the project")
        #expect(ActivityText.describe(tool("mcp__github__create_issue", [:])) == "Using create issue")
        #expect(ActivityText.describe(tool("Mystery", [:])) == "Using Mystery")
    }

    @Test func taskTakesFirstNonEmptyLine() {
        #expect(ActivityText.task(from: "\n  Fix the map  \nmore") == "Fix the map")
        #expect(ActivityText.task(from: "   ") == nil)
        #expect(ActivityText.task(from: nil) == nil)
    }
}

@Suite struct FormatTests {
    @Test func elapsed() {
        #expect(Format.elapsed(42) == "42 sec")
        #expect(Format.elapsed(124) == "2 min, 4 sec")
        #expect(Format.elapsed(5700) == "1 hr, 35 min")
        #expect(Format.elapsed(-5) == "0 sec")
    }

    @Test func tokens() {
        #expect(Format.tokens(950) == "950")
        #expect(Format.tokens(50_400) == "50.4k")
        #expect(Format.tokens(1_250_000) == "1.2M")
    }

    @Test func models() {
        #expect(Format.model("claude-opus-4-1-20250805") == "Opus")
        #expect(Format.model("claude-sonnet-5-5") == "Sonnet")
        #expect(Format.model("claude-haiku-5-5") == "Haiku")
        #expect(Format.family("claude-fable-5-2") == .fable)
        #expect(Format.model("gpt-5") == "gpt-5")
    }
}

@Suite struct GitTests {
    @Test func readsBranchFromRepoAndParents() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/guest-checkout\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        let nested = root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(GitBranch.read(from: root.path) == "feature/guest-checkout")
        #expect(GitBranch.read(from: nested.path) == "feature/guest-checkout")
    }

    @Test func detachedHeadShowsShortSha() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "0123456789abcdef0123456789abcdef01234567\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(GitBranch.read(from: root.path) == "0123456")
    }

    @Test func worktreeGitFile() throws {
        let root = tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real-gitdir")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try "ref: refs/heads/docs/inventory-webhooks\n".write(to: real.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try "gitdir: \(real.path)\n".write(to: work.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        #expect(GitBranch.read(from: work.path) == "docs/inventory-webhooks")
    }

    @Test func noRepoIsNil() { #expect(GitBranch.read(from: tempDir().path) == nil) }
}

@Suite struct TranscriptTests {
    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }

    private let user = ["type": "user", "message": ["role": "user", "content": "hello"]] as [String: Any]
    private let toolResult = ["type": "user", "message": ["role": "user", "content": [["type": "tool_result", "content": "ok"]]]] as [String: Any]
    private let assistant = ["type": "assistant", "message": ["model": "claude-opus-4-1", "content": [],
        "usage": ["input_tokens": 10, "output_tokens": 20, "cache_creation_input_tokens": 5, "cache_read_input_tokens": 9999]]] as [String: Any]
    private let sidechain = ["type": "assistant", "isSidechain": true, "message": ["model": "x", "usage": ["output_tokens": 500]]] as [String: Any]

    @Test func countsMessagesTokensAndModel() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        try (line(user) + line(toolResult) + line(assistant) + line(sidechain) + "garbage\n").write(to: file, atomically: true, encoding: .utf8)
        let stats = try #require(await TranscriptReader().stats(at: file.path))
        #expect(stats.messages == 2)          // user text + assistant; tool results and sidechains excluded
        #expect(stats.tokens == 35)           // cache reads excluded
        #expect(stats.model == "claude-opus-4-1")
    }

    @Test func incrementalAndPartialLines() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        let reader = TranscriptReader()
        try line(user).write(to: file, atomically: true, encoding: .utf8)
        #expect(await reader.stats(at: file.path)?.messages == 1)

        // A half-written line must not be counted or lost.
        let full = line(assistant)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(full.prefix(20).utf8))
        #expect(await reader.stats(at: file.path)?.messages == 1)
        try handle.write(contentsOf: Data(full.dropFirst(20).utf8))
        try handle.close()
        let after = try #require(await reader.stats(at: file.path))
        #expect(after.messages == 2)
        #expect(after.tokens == 35)
    }

    @Test func truncationResets() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        let reader = TranscriptReader()
        try (line(user) + line(user) + line(user)).write(to: file, atomically: true, encoding: .utf8)
        #expect(await reader.stats(at: file.path)?.messages == 3)
        try line(user).write(to: file, atomically: true, encoding: .utf8)
        #expect(await reader.stats(at: file.path)?.messages == 1)
    }

    @Test func longTranscriptsAreReadInPiecesAndHugeLinesSkipped() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("t.jsonl")
        let reader = TranscriptReader(chunkLimit: 4096)
        // Far more than one chunk is caught up in a single call.
        let many = String(repeating: line(user), count: 400)
        // A line bigger than a chunk is passed over instead of being read again forever.
        let huge = line(["type": "user", "message": ["content": String(repeating: "x", count: 20_000)]])
        try (many + huge + line(user)).write(to: file, atomically: true, encoding: .utf8)
        #expect(await reader.stats(at: file.path)?.messages == 401)
        #expect(await reader.stats(at: file.path)?.messages == 401)
    }

    @Test func missingFileIsNil() async { #expect(await TranscriptReader().stats(at: "/nonexistent/x.jsonl") == nil) }
}

@Suite struct RichSessionBookTests {
    @Test func knowsWhenNothingIsHappening() {
        var book = SessionBook()
        let t = Date(timeIntervalSince1970: 1000)
        #expect(!book.isActive(within: 600, now: t))
        book.apply(HookEvent.parse(Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s","cwd":"/tmp/p","prompt":"hi"}"#.utf8))!, now: t)
        #expect(book.isActive(within: 600, now: t.addingTimeInterval(599)))
        #expect(!book.isActive(within: 600, now: t.addingTimeInterval(601)))
        let before = book
        book.prune(now: t.addingTimeInterval(60))
        #expect(book == before)
    }

    @Test func buildsTaskActivityAndRecent() {
        var book = SessionBook()
        let t = Date(timeIntervalSince1970: 1000)
        book.apply(HookEvent(sessionID: "a", name: "SessionStart", cwd: "/x/aurora-shop", transcriptPath: "/t.jsonl"), now: t)
        book.apply(HookEvent(sessionID: "a", name: "UserPromptSubmit", cwd: "/x/aurora-shop", prompt: "Add cart persistence\nand more"), now: t)
        book.apply(HookEvent(sessionID: "a", name: "PreToolUse", toolName: "Edit", toolInput: ["file_path": .string("/x/Checkout.swift")]), now: t)
        let s = book.sessions["a"]
        #expect(s?.task == "Add cart persistence")
        #expect(s?.activity == "Editing Checkout.swift")
        #expect(s?.transcriptPath == "/t.jsonl")
        #expect(s?.startedAt == t)

        book.update("a", branch: "feature/x")
        book.update("a", stats: TranscriptStats(messages: 28, tokens: 50_400, model: "claude-opus-4-1"))
        #expect(book.sessions["a"]?.branch == "feature/x")
        #expect(book.sessions["a"]?.messages == 28)
        #expect(book.sessions["a"]?.model == "claude-opus-4-1")

        book.apply(HookEvent(sessionID: "a", name: "Stop"), now: t)
        #expect(book.sessions["a"]?.activity == nil)

        book.apply(HookEvent(sessionID: "a", name: "SessionEnd"), now: t.addingTimeInterval(60))
        #expect(book.sessions.isEmpty)
        #expect(book.recent.count == 1)
        #expect(book.recent[0].endedAt == t.addingTimeInterval(60))
        #expect(book.recent[0].task == "Add cart persistence")
    }

    @Test func recentIsCapped() {
        var book = SessionBook()
        for i in 0..<8 {
            book.apply(HookEvent(sessionID: "s\(i)", name: "SessionStart"))
            book.apply(HookEvent(sessionID: "s\(i)", name: "SessionEnd"))
        }
        #expect(book.recent.count == SessionBook.recentLimit)
    }

    @Test func staleSessionsMoveToRecent() {
        var book = SessionBook()
        book.apply(HookEvent(sessionID: "old", name: "SessionStart"), now: Date(timeIntervalSince1970: 0))
        book.prune(olderThan: 3600, now: Date(timeIntervalSince1970: 7200))
        #expect(book.sessions.isEmpty)
        #expect(book.recent.first?.id == "old")
    }
}
