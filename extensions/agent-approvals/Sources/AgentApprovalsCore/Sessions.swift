import Foundation

public enum AgentState: Sendable, Equatable {
    case idle, working, waiting
}

public struct AgentSession: Sendable, Identifiable, Equatable {
    public let id: String
    public var project: String
    public var cwd: String?
    public var branch: String?
    /// The latest prompt, shortened to a line.
    public var task: String?
    /// What it is doing right now, e.g. "Editing Model.swift".
    public var activity: String?
    public var model: String?
    public var transcriptPath: String?
    public var state: AgentState
    public var lastTool: String?
    public var startedAt: Date
    public var lastActivity: Date
    public var endedAt: Date?
    public var messages = 0
    public var tokens = 0

    public var isActive: Bool { endedAt == nil }
}

/// Tracks live and recently ended agent sessions from hook events.
public struct SessionBook: Sendable {
    public private(set) var sessions: [String: AgentSession] = [:]
    public private(set) var recent: [AgentSession] = []
    public static let recentLimit = 5
    public init() {}

    /// Newest activity first.
    public var ordered: [AgentSession] { sessions.values.sorted { $0.lastActivity > $1.lastActivity } }
    public var workingCount: Int { sessions.values.filter { $0.state == .working }.count }

    /// Returns true when the agent just finished a turn (Stop).
    @discardableResult
    public mutating func apply(_ event: HookEvent, now: Date = Date()) -> Bool {
        if event.name == "SessionEnd" {
            if var ended = sessions.removeValue(forKey: event.sessionID) {
                ended.endedAt = now
                ended.state = .idle
                ended.activity = nil
                recent.insert(ended, at: 0)
                if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
            }
            return false
        }
        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID, project: event.project, cwd: event.cwd, state: .idle, startedAt: now, lastActivity: now)
        if event.cwd != nil { session.project = event.project; session.cwd = event.cwd }
        if let path = event.transcriptPath { session.transcriptPath = path }
        session.lastActivity = now
        var finished = false
        switch event.name {
        case "SessionStart":
            session.state = .idle
        case "UserPromptSubmit":
            session.state = .working
            session.activity = nil
            if let task = ActivityText.task(from: event.prompt) { session.task = task }
        case "PreToolUse", "PostToolUse":
            session.state = .working
            session.lastTool = event.toolName
            session.activity = ActivityText.describe(event)
        case "PermissionRequest":
            session.state = .waiting
            session.lastTool = event.toolName
            session.activity = ActivityText.describe(event)
        case "Stop":
            finished = session.state != .idle
            session.state = .idle
            session.activity = nil
        default: break
        }
        sessions[event.sessionID] = session
        return finished
    }

    public mutating func resolvedPermission(session id: String, now: Date = Date()) {
        guard var session = sessions[id], session.state == .waiting else { return }
        session.state = .working
        session.lastActivity = now
        sessions[id] = session
    }

    public mutating func update(_ id: String, branch: String?) {
        guard sessions[id]?.branch != branch else { return }
        sessions[id]?.branch = branch
    }

    public mutating func update(_ id: String, stats: TranscriptStats) {
        guard var session = sessions[id] else { return }
        session.messages = stats.messages
        session.tokens = stats.tokens
        if let model = stats.model { session.model = model }
        sessions[id] = session
    }

    /// Moves sessions with no activity for `age` seconds (closed without SessionEnd) to Recent.
    public mutating func prune(olderThan age: TimeInterval = 6 * 3600, now: Date = Date()) {
        for (id, session) in sessions where now.timeIntervalSince(session.lastActivity) >= age {
            var ended = session
            ended.endedAt = session.lastActivity
            ended.state = .idle
            ended.activity = nil
            sessions[id] = nil
            recent.insert(ended, at: 0)
        }
        recent.sort { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }
}
