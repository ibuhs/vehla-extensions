import Foundation

/// When Today does work. Calendar changes are announced by the system, so in between it only wakes for the
/// moments that matter: a meeting about to start, one ending, midnight, or a slow periodic check.
public enum RefreshPlan {
    /// The longest Today goes without looking again.
    public static let idleInterval: TimeInterval = 15 * 60

    public static func nextWake(now: Date, events: [CalendarItem], leadMinutes: Int = 10,
                                calendar: Calendar = .current) -> Date {
        var candidates = [now.addingTimeInterval(idleInterval)]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) { candidates.append(midnight) }
        for event in events where !event.isAllDay {
            candidates += [event.start.addingTimeInterval(-TimeInterval(leadMinutes * 60)), event.start, event.end]
        }
        let next = candidates.filter { $0 > now }.min() ?? now.addingTimeInterval(idleInterval)
        return max(next, now.addingTimeInterval(1))
    }
}

/// When the AI brief may be requested. Every request is sent to a provider and may cost money.
public enum AIRefreshPolicy {
    /// Between automatic requests, whether or not the last one worked.
    public static let minimumInterval: TimeInterval = 10 * 60
    /// An unchanged day is summarised again after this long.
    public static let staleAfter: TimeInterval = 60 * 60

    /// - Parameters:
    ///   - key: what the brief would be about now (`AIBrief.changeKey`); `lastKey` is the one last asked about.
    ///   - lastAttempt: when a request was last made, successful or not.
    public static func shouldRequest(force: Bool, visible: Bool, now: Date, lastAttempt: Date?, lastSuccess: Date?,
                                     key: String, lastKey: String?) -> Bool {
        if force { return true }
        guard visible else { return false }   // nobody is looking
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < minimumInterval { return false }
        guard let lastSuccess else { return true }
        return key != lastKey || now.timeIntervalSince(lastSuccess) > staleAfter
    }
}
