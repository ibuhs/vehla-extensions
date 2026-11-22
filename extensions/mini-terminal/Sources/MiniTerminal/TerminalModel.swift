import AppKit
import MiniTerminalCore
import NotchKit
import SwiftUI
import VehlaNotchSDK

struct QuickCommand: Codable, Equatable, Identifiable {
    var title: String
    var command: String
    var id: String { title + "\u{1}" + command }
}

struct TerminalPrefs: Codable, Equatable {
    var themeID: String?
    var fontSize: Double?
    /// Show a running command in the closed Notch (timer, latest output, Stop). Off means the Notch stays clear.
    var showRunning: Bool?
    /// Prompt is just "%" and the cursor (default on). Applies on the next prompt, in every open session.
    var minimalPrompt: Bool?
    /// Hide the top bar until the pointer moves to the top edge, giving the terminal the full height.
    var autoHideHeader: Bool?
    var quickCommands: [QuickCommand]?
}

@MainActor
final class TerminalModel: ObservableObject {
    static let maxSessions = 3
    static let defaultQuickCommands = [
        QuickCommand(title: "ls", command: "ls -la"),
        QuickCommand(title: "git status", command: "git status -sb"),
        QuickCommand(title: "git log", command: "git log --oneline -10"),
        QuickCommand(title: "disk", command: "df -h /"),
        QuickCommand(title: "ports", command: "lsof -iTCP -sTCP:LISTEN -nP | head -12"),
        QuickCommand(title: "my ip", command: "ipconfig getifaddr en0"),
    ]

    @Published private(set) var sessions: [TerminalSession] = []
    @Published var activeID: UUID?
    @Published private(set) var prefs = TerminalPrefs()
    @Published private(set) var history = CommandHistory()
    @Published private(set) var status: String?
    /// Bumped to ask the terminal view to take keyboard focus.
    @Published private(set) var focusToken = 0

    private var notch: VehlaNotch?
    private var prefsStore: NKJSONStore<TerminalPrefs>?
    private var historyStore: NKJSONStore<CommandHistory>?
    private var ticker: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var tabVisible = false
    private var runShown = false
    private var completionUntil = Date.distantPast

    var active: TerminalSession? { sessions.first { $0.id == activeID } ?? sessions.first }
    var theme: TerminalTheme { .named(prefs.themeID) }
    var fontSize: Double { min(16, max(8, prefs.fontSize ?? 10.5)) }
    var showRunning: Bool { prefs.showRunning ?? true }
    var minimalPrompt: Bool { prefs.minimalPrompt ?? true }
    var autoHideHeader: Bool { prefs.autoHideHeader ?? false }
    var quickCommands: [QuickCommand] { prefs.quickCommands ?? Self.defaultQuickCommands }
    var prefsURL: URL? { prefsStore?.url }

    // MARK: Lifecycle

    func start(_ notch: VehlaNotch) {
        self.notch = notch
        let prefsStore = NKJSONStore<TerminalPrefs>(directory: notch.dataDirectory, name: "terminal.json")
        let historyStore = NKJSONStore<CommandHistory>(directory: notch.dataDirectory, name: "history.json")
        self.prefsStore = prefsStore
        self.historyStore = historyStore
        if let saved = prefsStore.load() { prefs = saved } else {
            prefs.quickCommands = Self.defaultQuickCommands
            prefsStore.save(prefs)      // write the defaults so there is a file to edit
        }
        history = historyStore.load() ?? CommandHistory()
        applyPromptFlag()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                self?.tick()
            }
        }
        tick()
    }

    func stop() {
        ticker?.cancel(); statusTask?.cancel(); saveTask?.cancel()
        flushHistory()
        sessions.forEach { $0.terminate() }
        sessions.removeAll()
        notch?.end("run")
        notch = nil
    }

    /// The shell starts the first time the tab opens, not when the Notch does.
    func ensureSession() {
        if sessions.isEmpty { newSession() }
    }

    func newSession() {
        guard sessions.count < Self.maxSessions, let notch else { return }
        do {
            let launch = try ShellIntegration.prepare(
                directory: notch.dataDirectory.appendingPathComponent("shell", isDirectory: true),
                shell: Self.userShell(), baseEnvironment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
            let session = TerminalSession(launch: launch, cwd: active?.cwd ?? NSHomeDirectory())
            session.onCommandFinished = { [weak self] result in self?.finished(result) }
            session.onLifecycle = { [weak self] in self?.tick() }
            sessions.append(session)
            activeID = session.id
            focusToken += 1
        } catch {
            flash("Couldn't prepare the shell: \(error.localizedDescription)")
        }
    }

    func close(_ session: TerminalSession) {
        session.terminate()
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id { activeID = sessions.last?.id }
        if sessions.isEmpty { newSession() }
    }

    /// The login shell from the user database; a GUI app's environment may not carry $SHELL.
    private static func userShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/bin/zsh"
    }

    func refocus() { focusToken += 1 }

    func select(_ session: TerminalSession) {
        activeID = session.id
        focusToken += 1
    }

    func tabVisibilityChanged(_ visible: Bool) {
        tabVisible = visible
        if visible { ensureSession(); focusToken += 1 }
        tick()
    }

    // MARK: History and commands

    private func finished(_ result: TerminalSession.Result) {
        history.record(command: result.command, cwd: result.cwd, exitCode: result.exitCode, duration: result.duration)
        scheduleSave()
        if runShown, !tabVisible {
            let ok = result.exitCode == 0
            completionUntil = Date().addingTimeInterval(6)
            notch?.show(VehlaNotchActivity(
                id: "run", systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill",
                title: Self.cut(result.command, 58),
                detail: (result.exitCode.map { $0 == 0 ? "" : "exit \($0) · " } ?? "") + Self.duration(result.duration),
                duration: 6))
        }
        runShown = false
    }

    func run(_ command: String) {
        guard let session = active else { return }
        if session.run(command) { focusToken += 1 } else { flash(session.running != nil ? "Something is already running" : "Can't run that here") }
    }

    func insert(_ command: String) {
        active?.insert(command)
        focusToken += 1
    }

    func togglePin(_ entry: HistoryEntry) { history.togglePin(entry.id); scheduleSave() }
    func removeHistory(_ entry: HistoryEntry) { history.remove(entry.id); scheduleSave() }
    func clearUnpinnedHistory() { history.clearUnpinned(); scheduleSave(); flash("History cleared (pinned kept)") }

    func copyLastOutput() {
        guard let text = active?.lastOutput, !text.isEmpty else { flash("No output to copy yet"); return }
        let ok = notch?.copy(text) ?? false
        flash(ok ? "Copied last output" : "Clipboard not allowed")
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { self?.flushHistory() }
        }
    }

    private func flushHistory() { historyStore?.save(history) }

    // MARK: Preferences

    func setTheme(_ theme: TerminalTheme) { prefs.themeID = theme.id; savePrefs() }
    func adjustFont(by delta: Double) { prefs.fontSize = min(16, max(8, fontSize + delta)); savePrefs() }
    func setShowRunning(_ on: Bool) { prefs.showRunning = on; savePrefs(); tick() }
    func setMinimalPrompt(_ on: Bool) { prefs.minimalPrompt = on; savePrefs(); applyPromptFlag() }
    func setAutoHideHeader(_ on: Bool) { prefs.autoHideHeader = on; savePrefs() }

    /// The shells watch a flag file: while it exists the prompt is minimal, so toggling takes effect live.
    private func applyPromptFlag() {
        guard let notch else { return }
        let dir = notch.dataDirectory.appendingPathComponent("shell", isDirectory: true)
        let flag = dir.appendingPathComponent("minimal-prompt")
        if minimalPrompt {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            FileManager.default.createFile(atPath: flag.path, contents: Data())
        } else {
            try? FileManager.default.removeItem(at: flag)
        }
    }

    private func savePrefs() { prefsStore?.save(prefs) }

    func revealPrefs() {
        guard let url = prefsURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealCwd() {
        guard let path = active?.cwd else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: Closed-Notch activities

    /// The closed Notch only ever shows the terminal while a command is actually running.
    private func tick() {
        guard let notch else { return }
        let now = Date()
        if tabVisible {
            // You're looking at the terminal; nothing needs to appear in the closed Notch.
            if runShown { notch.end("run"); runShown = false }
            return
        }
        guard showRunning, let runner = sessions.first(where: { $0.running != nil }), let r = runner.running else {
            if runShown, !sessions.contains(where: { $0.running != nil }), now >= completionUntil { runShown = false }
            return
        }
        // A command that finishes in under a second never flashes up.
        guard now.timeIntervalSince(r.startedAt) >= 1 else { return }
        runShown = true
        notch.show(VehlaNotchActivity(
            id: "run", systemImage: "terminal", title: Self.cut(r.command, 58),
            detail: runner.emulator.lastNonEmptyLine.map { Self.cut($0, 78) },
            timerStart: r.startedAt, duration: 28_000,
            buttons: [VehlaNotchActivityButton(id: "stop", title: "Stop (Ctrl-C)", systemImage: "stop.fill")]))
    }

    func activityAction(_ activityID: String, _ actionID: String) {
        if activityID == "run", actionID == "stop" {
            sessions.first { $0.running != nil }?.interrupt()
            return
        }
        notch?.openTab("terminal")
    }

    // MARK: Helpers

    func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.status = nil }
        }
    }

    static func cut(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    /// The real path with the home folder written as ~ (not shortened), e.g. ~/superwhisper/models.
    static func tildePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        let p = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        let parts = p.split(separator: "/", omittingEmptySubsequences: true)
        if parts.count <= 3 { return p }
        return (p.hasPrefix("~") ? "~/" : "/") + "…/" + parts.suffix(2).joined(separator: "/")
    }

    static func duration(_ seconds: Double) -> String {
        if seconds < 1 { return String(format: "%.0f ms", seconds * 1000) }
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        return "\(Int(seconds) / 60) min \(Int(seconds) % 60) s"
    }
}
