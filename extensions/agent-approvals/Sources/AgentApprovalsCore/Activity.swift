import Foundation

public enum ActivityText {
    /// A short present-tense description of what a tool call is doing, e.g. "Editing Model.swift".
    public static func describe(_ event: HookEvent) -> String {
        let tool = event.toolName ?? "tool"
        let file = event.filePath.map { ($0 as NSString).lastPathComponent }
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing \(file ?? "a file")"
        case "Read": return "Reading \(file ?? "a file")"
        case "Bash":
            let line = (event.command ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return line.isEmpty ? "Running a command" : "Running \(RiskAssessor.truncate(line, 70))"
        case "Grep", "Glob": return "Searching the project"
        case "Task", "Agent": return "Running a subagent"
        case "WebFetch", "WebSearch": return "Browsing the web"
        case "TodoWrite": return "Planning"
        default:
            if tool.hasPrefix("mcp__"), let last = tool.components(separatedBy: "__").last, !last.isEmpty {
                return "Using \(last.replacingOccurrences(of: "_", with: " "))"
            }
            return "Using \(tool)"
        }
    }

    /// The first line of a prompt, trimmed for a one-line row.
    public static func task(from prompt: String?) -> String? {
        guard let line = prompt?.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        return RiskAssessor.truncate(line, 160)
    }
}
