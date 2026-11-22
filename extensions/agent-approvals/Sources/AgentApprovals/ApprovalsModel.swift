import AgentApprovalsCore
import AppKit
import NotchKit
import SwiftUI
import VehlaNotchSDK

struct PendingApproval: Identifiable {
    let id = UUID()
    let event: HookEvent
    let summary: ApprovalSummary
    let reply: HookServer.Reply
    let received = Date()
}

struct HistoryItem: Identifiable {
    enum Outcome { case allowed, autoAllowed, denied, expired }
    let id = UUID()
    let title: String
    let detail: String
    let project: String
    let outcome: Outcome
    let date: Date
}

@MainActor
final class ApprovalsModel: ObservableObject {
    @Published private(set) var book = SessionBook()
    @Published private(set) var pending: [PendingApproval] = []
    @Published private(set) var history: [HistoryItem] = []
    @Published private(set) var serverError: String?
    @Published private(set) var scriptInstalled = HookInstaller.scriptInstalled
    @Published var status: String?

    private var rules = AllowRules()
    private var notch: VehlaNotch?
    private var server: HookServer?
    private var housekeeping: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    /// A permission request that nobody answers falls back to Claude Code's own prompt.
    private let answerWindow: TimeInterval = 95

    private let reader = TranscriptReader()

    var sessions: [AgentSession] { book.ordered }
    var recentSessions: [AgentSession] { book.recent }

    // MARK: Lifecycle

    func start(_ notch: VehlaNotch) {
        self.notch = notch
        scriptInstalled = HookInstaller.scriptInstalled
        let server = HookServer(path: HookInstaller.socketPath) { [weak self] data, reply in
            Task { @MainActor in self?.receive(data, reply: reply) }
        }
        do {
            try server.start()
            self.server = server
            serverError = nil
        } catch {
            serverError = "Couldn't listen on the hook socket (\(error))."
        }
    }

    /// Runs only while there is something to watch: a request waiting for an answer, or a session that was busy
    /// in the last ten minutes. With no agents running this extension does no work at all.
    private func keepHouse() {
        guard housekeeping == nil else { return }
        housekeeping = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.tick()
                await self.refreshStats()
                if self.pending.isEmpty && !self.book.isActive(within: 600) {
                    self.housekeeping = nil
                    return
                }
            }
        }
    }

    /// Opening the tab brings anything that went quiet up to date.
    func tabVisibilityChanged(_ visible: Bool) {
        guard visible else { return }
        tick()
        Task { await refreshStats() }
    }

    /// Publishes only real changes; assigning an equal value would still redraw the tab.
    private func updateBook(_ change: (inout SessionBook) -> Void) {
        var copy = book
        change(&copy)
        if copy != book { book = copy }
    }

    func stop() {
        housekeeping?.cancel()
        housekeeping = nil
        statusTask?.cancel()
        for item in pending { item.reply(nil) }
        pending.removeAll()
        server?.stop()
        server = nil
        notch?.end("approval")
        notch = nil
    }

    private func tick() {
        updateBook { $0.prune() }
        let now = Date()
        for item in pending where now.timeIntervalSince(item.received) > answerWindow {
            resolve(item.id, decision: nil, outcome: .expired)
        }
    }

    // MARK: Events

    private func receive(_ data: Data, reply: @escaping HookServer.Reply) {
        guard let event = HookEvent.parse(data) else { reply(nil); return }
        keepHouse()
        let finished = book.apply(event)
        trackDetails(for: event)
        guard event.isBlocking else {
            reply(nil)
            if event.name == "SessionEnd" { rules.forget(session: event.sessionID) }
            if finished { announceFinished(event) }
            return
        }
        let summary = RiskAssessor.summarize(event)
        if rules.allows(event) {
            reply(HookResponse.render(.allow, for: event))
            book.resolvedPermission(session: event.sessionID)
            record(event, summary, .autoAllowed)
            return
        }
        pending.append(PendingApproval(event: event, summary: summary, reply: reply))
        refreshActivity()
    }

    /// Branch and transcript-derived counts, refreshed on the events that change them.
    private func trackDetails(for event: HookEvent) {
        guard let session = book.sessions[event.sessionID] else { return }
        if session.branch == nil || event.name == "UserPromptSubmit" || event.name == "SessionStart" {
            book.update(session.id, branch: GitBranch.read(from: session.cwd))
        }
        if ["SessionStart", "UserPromptSubmit", "Stop"].contains(event.name) {
            Task { await refreshStats() }
        }
    }

    func refreshStats() async {
        let sessions = Array(book.sessions.values)
        await reader.keepOnly(Set(sessions.compactMap(\.transcriptPath)))
        for session in sessions {
            guard let path = session.transcriptPath, let stats = await reader.stats(at: path) else { continue }
            updateBook { $0.update(session.id, stats: stats) }
        }
    }

    func decide(_ item: PendingApproval, allow: Bool, always: Bool = false) {
        if allow && always { rules.add(item.event) }
        resolve(item.id, decision: allow ? .allow : .deny("Denied from the Vehla Notch"),
                outcome: allow ? .allowed : .denied)
    }

    private func resolve(_ id: UUID, decision: HookDecision?, outcome: HistoryItem.Outcome) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        let item = pending.remove(at: index)
        item.reply(HookResponse.render(decision, for: item.event))
        book.resolvedPermission(session: item.event.sessionID)
        record(item.event, item.summary, outcome)
        refreshActivity()
    }

    private func record(_ event: HookEvent, _ summary: ApprovalSummary, _ outcome: HistoryItem.Outcome) {
        history.insert(HistoryItem(title: summary.title, detail: summary.detail, project: event.project,
                                   outcome: outcome, date: Date()), at: 0)
        if history.count > 30 { history.removeLast(history.count - 30) }
    }

    // MARK: Notch activities

    private func refreshActivity() {
        guard let notch else { return }
        guard let head = pending.first else { notch.end("approval"); return }
        let more = pending.count - 1
        let tool = head.summary.title
        let detail = RiskAssessor.truncate(
            head.summary.detail.replacingOccurrences(of: "\n", with: " ") + (more > 0 ? "  +\(more)" : ""), 78)
        notch.show(VehlaNotchActivity(
            id: "approval",
            systemImage: head.summary.risk == .high ? "exclamationmark.shield.fill" : "hand.raised.fill",
            title: RiskAssessor.truncate("\(head.event.project) · \(tool)", 58),
            detail: detail,
            tintHex: Self.hex(head.summary.risk),
            buttons: [
                VehlaNotchActivityButton(id: "approve", title: "Approve", systemImage: "checkmark"),
                VehlaNotchActivityButton(id: "deny", title: "Deny", systemImage: "xmark"),
            ]))
    }

    private func announceFinished(_ event: HookEvent) {
        notch?.show(VehlaNotchActivity(
            id: "agents", systemImage: "checkmark.circle.fill",
            title: RiskAssessor.truncate("\(event.project) finished", 58),
            detail: "Agent is waiting for you", tintHex: NK.Hex.success, duration: 6))
    }

    func activityAction(_ activityID: String, _ actionID: String) {
        guard activityID == "approval", let head = pending.first else {
            if activityID == "agents" { notch?.openTab("agents") }
            return
        }
        switch actionID {
        case "approve": decide(head, allow: true)
        case "deny": decide(head, allow: false)
        default: notch?.openTab("agents")
        }
    }

    static func hex(_ risk: Risk) -> String {
        switch risk {
        case .low: return NK.Hex.success
        case .medium: return NK.Hex.warning
        case .high: return NK.Hex.danger
        }
    }

    // MARK: Setup

    func installScript() {
        do {
            try HookInstaller.installScript()
            scriptInstalled = true
            flash("Hook script installed")
        } catch {
            flash("Couldn't install: \(error.localizedDescription)")
        }
    }

    func copySnippet() {
        let ok = notch?.copy(HookInstaller.settingsSnippet()) ?? false
        flash(ok ? "Settings copied. Merge into ~/.claude/settings.json" : "Clipboard not allowed")
    }

    private func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self.status = nil }
        }
    }
}
