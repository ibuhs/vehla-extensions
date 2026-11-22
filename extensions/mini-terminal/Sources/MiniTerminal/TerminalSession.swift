import AppKit
import MiniTerminalCore

final class ByteQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var scheduled = false

    /// Returns true when the caller should schedule a drain (the first push since the last take).
    func push(_ d: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        data.append(d)
        let first = !scheduled
        scheduled = true
        return first
    }

    func take() -> Data {
        lock.lock(); defer { lock.unlock() }
        let d = data
        data = Data()
        scheduled = false
        return d
    }
}

final class WeakSession: @unchecked Sendable {
    weak var value: TerminalSession?
    init(_ value: TerminalSession) { self.value = value }
}

/// One shell on one pseudo-terminal, plus everything the Notch wants to know about it.
@MainActor
final class TerminalSession: ObservableObject, Identifiable {
    struct Running: Equatable {
        var command: String
        var startedAt: Date
    }

    struct Result: Equatable {
        var command: String
        var exitCode: Int?
        var duration: Double
        var finishedAt: Date
        var cwd: String
    }

    let id = UUID()
    let emulator = TerminalEmulator(cols: 90, rows: 8)
    let launch: ShellLaunch

    @Published private(set) var cwd: String
    @Published private(set) var running: Running?
    @Published private(set) var lastResult: Result?
    @Published private(set) var isAlive = true

    /// The view redraws when this fires; it is coalesced to roughly 80 Hz.
    var onDisplay: (() -> Void)?
    var onCommandFinished: ((Result) -> Void)?
    /// A command started or finished, or the shell exited.
    var onLifecycle: (() -> Void)?

    private var pty: PTYSession?
    private let queue = ByteQueue()
    private var pendingText: String?
    private var startedCwd: String
    private var poll: Timer?
    private var idlePolls = 0
    private var displayScheduled = false
    private var size = (cols: 90, rows: 8)

    init(launch: ShellLaunch, cwd: String) {
        self.launch = launch
        self.cwd = cwd
        self.startedCwd = cwd
        emulator.scrollbackLimit = 3000
        emulator.onEvent = { [weak self] event in self?.handle(event) }
        emulator.onResponse = { [weak self] bytes in self?.pty?.write(bytes) }
    }

    // MARK: Lifecycle

    func ensureStarted(cols: Int, rows: Int) {
        guard pty == nil, isAlive else { return }
        size = (cols, rows)
        emulator.resize(cols: cols, rows: rows)
        start()
    }

    private func start() {
        do {
            let session = try PTYSession(executable: launch.executable, arguments: launch.arguments,
                                         environment: launch.environment, directory: cwd, cols: size.cols, rows: size.rows)
            let weak = WeakSession(self), queue = queue
            session.start(
                onData: { data in
                    if queue.push(data) { Task { @MainActor in weak.value?.drain() } }
                },
                onExit: { code in Task { @MainActor in weak.value?.shellExited(code) } })
            pty = session
            isAlive = true
            if !launch.reportsCommands { startPolling() }
        } catch {
            isAlive = false
            emulator.feed("Couldn't start \(launch.name): \(error.localizedDescription)\r\n")
            scheduleDisplay()
        }
    }

    /// Starts a fresh shell after the old one exited.
    func restart() {
        guard !isAlive else { return }
        pty = nil
        emulator.feed("\u{1B}[2J\u{1B}[H")
        isAlive = true
        start()
        onLifecycle?()
    }

    func terminate() {
        poll?.invalidate(); poll = nil
        pty?.terminate()
        pty = nil
        isAlive = false
    }

    private func shellExited(_ code: Int32) {
        isAlive = false
        poll?.invalidate(); poll = nil
        if running != nil { running = nil }
        emulator.feed("\r\n\u{1B}[2m[\(launch.name) exited with status \(code). Press Return to start a new shell.]\u{1B}[0m\r\n")
        scheduleDisplay()
        onLifecycle?()
    }

    // MARK: Output

    private func drain() {
        let data = queue.take()
        guard !data.isEmpty else { return }
        emulator.feed(data)
        scheduleDisplay()
    }

    private func scheduleDisplay() {
        guard !displayScheduled else { return }
        displayScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(12))
            self?.displayScheduled = false
            self?.onDisplay?()
        }
    }

    // MARK: Shell events

    private func handle(_ event: TerminalEvent) {
        switch event {
        case .cwd(let path): if path != cwd { cwd = path }
        case .commandText(let text): pendingText = text
        case .commandStart: beginRunning(pendingText ?? pty?.foregroundName ?? "command")
        case .commandEnd(let code): endRunning(code)
        case .promptStart, .bell, .title: break
        }
    }

    private func beginRunning(_ text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        running = Running(command: command.isEmpty ? "command" : command, startedAt: Date())
        startedCwd = cwd
        onLifecycle?()
    }

    private func endRunning(_ code: Int?) {
        guard let r = running else { return }
        let result = Result(command: r.command, exitCode: code, duration: Date().timeIntervalSince(r.startedAt),
                            finishedAt: Date(), cwd: startedCwd)
        lastResult = result
        running = nil
        pendingText = nil
        idlePolls = 0
        onCommandFinished?(result)
        onLifecycle?()
    }

    /// Shells that don't report command boundaries (bash, fish) are watched through the terminal's foreground job.
    private func startPolling() {
        poll?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollForeground() }
        }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func pollForeground() {
        let busy = pty?.isBusy ?? false
        if busy, running == nil {
            beginRunning(pty?.foregroundName ?? "command")
            idlePolls = 0
        } else if !busy, running != nil {
            idlePolls += 1
            if idlePolls >= 2 { endRunning(nil) }
        } else {
            idlePolls = 0
        }
    }

    // MARK: Input

    func sendKey(_ key: TerminalKey, modifiers: KeyModifiers) {
        if !isAlive {
            if key == .enter { restart() }
            return
        }
        pty?.write(KeyEncoder.encode(key, modifiers: modifiers, applicationCursor: emulator.applicationCursorKeys))
    }

    func paste(_ text: String) {
        guard isAlive else { return }
        pty?.write(KeyEncoder.paste(text, bracketed: emulator.bracketedPaste))
    }

    /// Puts a command on the prompt, replacing whatever was typed, without running it.
    func insert(_ command: String) {
        guard isAlive, running == nil, !command.contains("\n") else { return }
        pty?.write([0x15] + KeyEncoder.paste(command, bracketed: emulator.bracketedPaste))
    }

    /// Runs a command. Returns false if something is already running or the line is not a single command.
    @discardableResult
    func run(_ command: String) -> Bool {
        guard isAlive, running == nil, !command.contains("\n"), !command.isEmpty else { return false }
        pty?.write([0x15] + Array(command.utf8) + [0x0D])
        return true
    }

    func interrupt() { pty?.interrupt() }

    func clear() {
        emulator.clearAll()
        if running == nil { pty?.write([0x0C]) }   // Ctrl-L redraws the prompt
        scheduleDisplay()
    }

    func resize(cols: Int, rows: Int) {
        guard cols != size.cols || rows != size.rows else { return }
        size = (cols, rows)
        emulator.resize(cols: cols, rows: rows)
        pty?.resize(cols: cols, rows: rows)
        scheduleDisplay()
    }

    var lastOutput: String { emulator.lastOutput }

    func copyLastOutput() { /* the model copies through the host; the context menu falls back to the pasteboard */
        let text = emulator.lastOutput
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    var foregroundName: String? { pty?.foregroundName }
}
