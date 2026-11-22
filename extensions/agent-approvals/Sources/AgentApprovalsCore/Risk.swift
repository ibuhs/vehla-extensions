import Foundation

public enum Risk: Int, Comparable, Sendable {
    case low, medium, high
    public static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Review"
        case .high: return "High risk"
        }
    }
}

public struct ApprovalSummary: Sendable, Equatable {
    public let title: String
    public let detail: String
    public let risk: Risk
}

public enum RiskAssessor {
    private static let highCommand: [String] = [
        #"\brm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-r\b|--recursive)"#,
        #"\bsudo\b"#, #"git\s+push\b.*(--force|\s-f\b)"#, #"git\s+reset\s+--hard"#,
        #"git\s+clean\s+-[a-z]*f"#, #"(curl|wget)\b[^|]*\|\s*(sudo\s+)?(sh|bash|zsh)"#,
        #"\b(chmod|chown)\s+-R"#, #"\bmkfs\b"#, #"\bdd\s+if="#, #">\s*/dev/(sd|disk|nvme)"#,
        #":\(\)\s*\{"#, #"(?i)\bdrop\s+(table|database)\b"#, #"\bdiskutil\s+erase"#,
    ]
    private static let mediumCommand: [String] = [
        #"\brm\b"#, #"git\s+push\b"#, #"\b(npm|pnpm|yarn)\s+publish\b"#,
        #"\b(npm|pnpm|yarn|pip3?|brew|gem|cargo)\s+(install|add|uninstall)\b"#,
        #"\bkill(all)?\b"#, #"\bmv\b.*\s/"#, #"\bcurl\b.*\s-X\s*(POST|PUT|DELETE)"#,
    ]
    private static let sensitivePaths = ["/.ssh/", "/.aws/", "/.gnupg/", "/etc/", ".env", ".zshrc", ".bashrc", ".zprofile", "/Library/LaunchAgents/"]

    public static func assess(_ event: HookEvent) -> Risk {
        if let command = event.command {
            if highCommand.contains(where: { matches($0, command) }) { return .high }
            if mediumCommand.contains(where: { matches($0, command) }) { return .medium }
            return .low
        }
        if let path = event.filePath {
            if sensitivePaths.contains(where: { path.contains($0) }) { return .high }
            return event.toolName == "Read" ? .low : .medium
        }
        return .low
    }

    public static func summarize(_ event: HookEvent) -> ApprovalSummary {
        let tool = event.toolName ?? "Tool"
        let detail: String
        if let command = event.command {
            detail = command.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let path = event.filePath {
            detail = (path as NSString).abbreviatingWithTildeInPath
        } else if let message = event.message {
            detail = message
        } else {
            detail = "Requests permission"
        }
        return ApprovalSummary(title: tool, detail: truncate(detail, 400), risk: assess(event))
    }

    public static func truncate(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Session-scoped "always allow" rules. High-risk requests never match a rule.
public struct AllowRules: Sendable {
    private var keys: Set<String> = []
    public init() {}

    public static func key(for event: HookEvent) -> String {
        let tool = event.toolName ?? "Tool"
        guard let command = event.command else { return "\(event.sessionID)|\(tool)" }
        let words = command.split(separator: " ", omittingEmptySubsequences: true).prefix(2).joined(separator: " ")
        return "\(event.sessionID)|\(tool)|\(words)"
    }

    /// Whether "always allow" may apply: never for high-risk requests, and never for a shell command
    /// that chains or redirects (`a && b`, `a; b`, pipes, substitutions), because approving `git status`
    /// must not also approve whatever is appended to it.
    public static func isRememberable(_ event: HookEvent) -> Bool {
        guard RiskAssessor.assess(event) < .high else { return false }
        guard let command = event.command else { return true }
        return !command.contains { ";&|`$<>(){}\n\r".contains($0) }
    }

    public mutating func add(_ event: HookEvent) {
        guard Self.isRememberable(event) else { return }
        keys.insert(Self.key(for: event))
    }

    public func allows(_ event: HookEvent) -> Bool {
        Self.isRememberable(event) && keys.contains(Self.key(for: event))
    }

    public mutating func forget(session: String) { keys = keys.filter { !$0.hasPrefix(session + "|") } }
}
