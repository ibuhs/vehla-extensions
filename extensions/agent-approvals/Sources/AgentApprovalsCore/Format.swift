import Foundation

public enum Format {
    /// "42 sec", "2 min, 4 sec", "1 hr, 35 min".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total) sec" }
        if total < 3600 { return "\(total / 60) min, \(total % 60) sec" }
        return "\(total / 3600) hr, \((total % 3600) / 60) min"
    }

    /// "950", "50.4k", "1.2M".
    public static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1000)
        default: return String(format: "%.1fM", Double(n) / 1_000_000)
        }
    }

    public enum ModelFamily: Sendable { case opus, sonnet, haiku, fable, other }

    public static func family(_ model: String) -> ModelFamily {
        let m = model.lowercased()
        if m.contains("opus") { return .opus }
        if m.contains("sonnet") { return .sonnet }
        if m.contains("haiku") { return .haiku }
        if m.contains("fable") { return .fable }
        return .other
    }

    public static func model(_ id: String) -> String {
        switch family(id) {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .fable: return "Fable"
        case .other: return RiskAssessor.truncate(id.replacingOccurrences(of: "claude-", with: ""), 14)
        }
    }
}
