import Foundation
import Testing
@testable import MiniTerminalCore

/// Collects output and exit status from a PTY on its own queue.
private final class Capture: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var exit: Int32?
    func add(_ d: Data) { lock.lock(); buffer.append(d); lock.unlock() }
    func finish(_ code: Int32) { lock.lock(); exit = code; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: buffer, as: UTF8.self) }
    var exitCode: Int32? { lock.lock(); defer { lock.unlock() }; return exit }
}

private func wait(timeout: Double = 8, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

private final class Keeper: @unchecked Sendable {
    static let shared = Keeper()
    private let lock = NSLock()
    private var sessions: [PTYSession] = []
    func hold(_ s: PTYSession) { lock.lock(); sessions.append(s); lock.unlock() }
}

private func spawn(_ exe: String, _ args: [String], env: [String: String] = [:], dir: String? = nil,
                   cols: Int = 40, rows: Int = 10) throws -> (PTYSession, Capture) {
    let cap = Capture()
    let pty = try PTYSession(executable: exe, arguments: args,
                             environment: ["PATH": "/usr/bin:/bin", "TERM": "xterm-256color"].merging(env) { $1 },
                             directory: dir, cols: cols, rows: rows)
    pty.start(onData: { cap.add($0) }, onExit: { cap.finish($0) })
    Keeper.shared.hold(pty)
    return (pty, cap)
}

@Suite(.serialized) struct PTYTests {
    @Test func runsAProgramAndReportsItsExitStatus() async throws {
        let (pty, cap) = try spawn("/bin/sh", ["-c", "echo hello world; exit 7"])
        #expect(await wait { cap.exitCode != nil }, "pid \(pty.pid) alive=\(kill(pty.pid, 0) == 0) text=\(cap.text.debugDescription)")
        #expect(cap.exitCode == 7)
        #expect(cap.text.contains("hello world"))
    }

    @Test func passesEnvironmentAndWorkingDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let (pty, cap) = try spawn("/bin/sh", ["-c", "pwd; echo $FOO"], env: ["FOO": "bar"], dir: dir.path)
        #expect(await wait { cap.exitCode != nil }, "pid \(pty.pid) alive=\(kill(pty.pid, 0) == 0) busy=\(pty.isBusy) text=\(cap.text.debugDescription)")
        #expect(cap.text.contains("bar"))
        #expect(cap.text.contains(dir.lastPathComponent))
    }

    @Test func isARealTerminalWithEchoAndWindowSize() async throws {
        let (pty, cap) = try spawn("/bin/sh", ["-c", "tty >/dev/null && stty size; read x; stty size"], cols: 40, rows: 10)
        #expect(await wait { cap.text.contains("10 40") })
        pty.resize(cols: 100, rows: 30)
        pty.write("go\n")
        #expect(await wait { cap.text.contains("30 100") })
        #expect(await wait { cap.exitCode != nil })
        #expect(cap.exitCode == 0)
    }

    @Test func writesReachTheProgramAndComeBackEchoed() async throws {
        let (pty, cap) = try spawn("/bin/cat", [])
        pty.write("typed text\n")
        #expect(await wait { cap.text.components(separatedBy: "typed text").count >= 3 })   // tty echo, then cat's output
        pty.write([0x04])                                                                      // Ctrl-D ends cat
        #expect(await wait { cap.exitCode != nil })
        #expect(cap.exitCode == 0)
    }

    @Test func seesWhenACommandIsRunningAndCanInterruptIt() async throws {
        let (pty, cap) = try spawn("/bin/sh", ["-i"], env: ["PS1": "$ ", "ENV": ""])
        #expect(await wait { cap.text.contains("$ ") })
        #expect(!pty.isBusy)
        pty.write("sleep 30\n")
        #expect(await wait { pty.isBusy })
        #expect(await wait { pty.foregroundName == "sleep" })
        pty.interrupt()
        #expect(await wait { !pty.isBusy }, "pid \(pty.pid) fg=\(String(describing: pty.foregroundProcessGroup)) text=\(cap.text.debugDescription)")
        pty.write("exit 3\n")
        #expect(await wait { cap.exitCode != nil })
        #expect(cap.exitCode == 3)
    }

    @Test func terminateEndsAStubbornShell() async throws {
        let (pty, _) = try spawn("/bin/sh", ["-c", "trap '' INT; sleep 60"])
        try await Task.sleep(for: .milliseconds(200))
        pty.terminate()
        #expect(await wait { kill(pty.pid, 0) != 0 })      // the process is gone
    }

    @Test func aMissingProgramFailsCleanly() {
        #expect(throws: PTYError.self) {
            _ = try PTYSession(executable: "/nonexistent/shell", arguments: [], environment: [:], directory: nil, cols: 80, rows: 24)
        }
    }
}

/// End to end: a real zsh on a PTY, with our integration, feeding the emulator.
private final class Rig: @unchecked Sendable {
    let lock = NSLock()
    let emulator = TerminalEmulator(cols: 80, rows: 24)
    private var events: [TerminalEvent] = []
    private let queue = DispatchQueue(label: "rig")
    var exited: Int32?
    var snapshot: [TerminalEvent] { lock.lock(); defer { lock.unlock() }; return events }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }
    /// Events that arrived after the first `index`.
    func events(after index: Int) -> [TerminalEvent] { lock.lock(); defer { lock.unlock() }; return Array(events.dropFirst(index)) }
    var screenText: String { lock.lock(); defer { lock.unlock() }; return (0..<emulator.rows).map { emulator.text(row: $0) }.joined(separator: "\n") }
    func feed(_ d: Data) { lock.lock(); emulator.feed(d); lock.unlock() }
    init() { emulator.onEvent = { [weak self] e in self?.events.append(e) } }
}

@Suite(.serialized) struct ZshIntegrationTests {
    @Test func reportsPromptsCommandsExitCodesAndDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vmt-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // The user's own zshrc must still run.
        try "export VMT_USER_RC=loaded\nPROMPT='%# '\n".write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        let launch = try ShellIntegration.prepare(
            directory: root.appendingPathComponent("shell"), shell: "/bin/zsh",
            baseEnvironment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "SHELL": "/bin/zsh"], home: home.path)
        #expect(launch.reportsCommands && launch.name == "zsh")
        #expect(launch.environment["TERM"] == "xterm-256color")

        let rig = Rig()
        let pty = try PTYSession(executable: launch.executable, arguments: launch.arguments, environment: launch.environment,
                                 directory: home.path, cols: 80, rows: 24)
        rig.emulator.onResponse = { pty.write($0) }
        pty.start(onData: { rig.feed($0) }, onExit: { rig.exited = $0 })
        defer { pty.terminate() }

        #expect(await wait(timeout: 15) { rig.snapshot.contains(.promptStart) })
        try await Task.sleep(for: .milliseconds(200))

        func run(_ line: String, until end: TerminalEvent) async -> [TerminalEvent] {
            let mark = rig.count
            pty.write(line + "\n")
            _ = await wait { rig.events(after: mark).contains(end) }
            return rig.events(after: mark)
        }

        let echo = await run("echo $VMT_USER_RC", until: .commandEnd(0))
        #expect(echo.contains(.commandText("echo $VMT_USER_RC")), "events: \(echo)")
        #expect(echo.firstIndex(of: .commandStart)! < echo.firstIndex(of: .commandEnd(0))!)
        #expect(rig.screenText.contains("loaded"))               // the user's config ran
        #expect(rig.emulator.lastOutput == "loaded")             // and only the output was captured

        let failed = await run("false", until: .commandEnd(1))
        #expect(failed.contains(.commandEnd(1)))

        let moved = await run("cd /tmp", until: .promptStart)
        #expect(moved.contains { if case .cwd(let p) = $0 { return p.hasSuffix("/tmp") }; return false })

        // A favorite folder: a name with a space and a quote, typed the way the star menu types it.
        let project = root.appendingPathComponent("My Project's; echo pwned")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let line = FavoriteFolders.cdCommand(for: project.path)
        let jumped = await run(String(line), until: .promptStart)
        #expect(jumped.contains { if case .cwd(let p) = $0 { return p.hasSuffix("echo pwned") }; return false }, "events: \(jumped)")
        #expect(!rig.screenText.contains("\npwned"))
        // The shell reports the line as typed, so the leading space keeps it out of the history.
        #expect(jumped.contains { if case .commandText(let t) = $0 { return !CommandHistory.shouldRecord(t) }; return false }, "events: \(jumped)")

        let multi = await run("printf 'a b\\nc d\\n'; sh -c 'exit 5'", until: .commandEnd(5))
        #expect(multi.contains(.commandEnd(5)))
        #expect(rig.emulator.lastOutput == "a b\nc d")

        pty.write("exit\n")
        #expect(await wait { rig.exited != nil })
    }

    @Test func minimalPromptSwitchesLiveAndRestoresYourOwn() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vmt-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A prompt theme that sets the prompt before every prompt, like powerlevel10k or starship do.
        try "PROMPT='ORIGINAL> '\nRPROMPT='[right]'\nthemed() { PROMPT='ORIGINAL> '; RPROMPT='[right]' }\nprecmd_functions+=(themed)\n"
            .write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)

        let shellDir = root.appendingPathComponent("shell")
        let launch = try ShellIntegration.prepare(
            directory: shellDir, shell: "/bin/zsh",
            baseEnvironment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": home.path, "SHELL": "/bin/zsh"], home: home.path)
        let flag = URL(fileURLWithPath: try #require(launch.environment["VEHLA_PROMPT_FLAG"]))
        #expect(flag.path == shellDir.appendingPathComponent("minimal-prompt").path)
        FileManager.default.createFile(atPath: flag.path, contents: Data())

        let rig = Rig()
        let pty = try PTYSession(executable: launch.executable, arguments: launch.arguments, environment: launch.environment,
                                 directory: home.path, cols: 80, rows: 24)
        rig.emulator.onResponse = { pty.write($0) }
        pty.start(onData: { rig.feed($0) }, onExit: { rig.exited = $0 })
        defer { pty.terminate() }
        #expect(await wait(timeout: 15) { rig.snapshot.contains(.promptStart) })
        try await Task.sleep(for: .milliseconds(300))

        // Minimal prompt wins over the theme: just "%", no text from the user's prompt, nothing on the right.
        #expect(rig.screenText.contains("%"), "screen: \(rig.screenText)")
        #expect(!rig.screenText.contains("ORIGINAL"), "screen: \(rig.screenText)")
        #expect(!rig.screenText.contains("[right]"))

        func prompt(after line: String) async {
            let mark = rig.count
            pty.write(line + "\n")
            _ = await wait { rig.events(after: mark).contains(.promptStart) }
            try? await Task.sleep(for: .milliseconds(250))
        }
        await prompt(after: "echo one")
        #expect(!rig.screenText.contains("ORIGINAL"))

        try FileManager.default.removeItem(at: flag)                       // switch it off, live
        await prompt(after: "echo two")
        await prompt(after: "echo three")
        #expect(rig.screenText.contains("ORIGINAL> "), "screen: \(rig.screenText)")   // the user's own prompt is back
    }

    @Test func writesOnlyPrivateFilesAndLeavesTheUsersConfigAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vmt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let launch = try ShellIntegration.prepare(directory: root, shell: "/bin/zsh",
                                                  baseEnvironment: ["HOME": "/Users/x", "ZDOTDIR": "/Users/x/.config/zsh", "TERM_SESSION_ID": "abc"],
                                                  home: "/Users/x")
        #expect(launch.environment["VEHLA_USER_ZDOTDIR"] == "/Users/x/.config/zsh")     // the user's own ZDOTDIR is honoured
        #expect(launch.environment["ZDOTDIR"] == root.appendingPathComponent("zsh").path)
        #expect(launch.environment["TERM_SESSION_ID"] == nil)
        let attrs = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("zsh/.zshrc").path)
        #expect((attrs[.posixPermissions] as? Int) == 0o600)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect((dirAttrs[.posixPermissions] as? Int) == 0o700)
    }

    @Test func bashAndUnknownShells() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vmt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bash = try ShellIntegration.prepare(directory: root, shell: "/bin/bash", baseEnvironment: [:], home: "/Users/x")
        #expect(bash.arguments.first == "--rcfile" && !bash.reportsCommands)
        #expect(FileManager.default.fileExists(atPath: bash.arguments[1]))
        let fish = try ShellIntegration.prepare(directory: root, shell: "/opt/homebrew/bin/fish", baseEnvironment: [:], home: "/Users/x")
        #expect(fish.arguments.isEmpty && fish.name == "fish")
        #expect(fish.environment["LANG"] == "en_US.UTF-8")
    }
}
