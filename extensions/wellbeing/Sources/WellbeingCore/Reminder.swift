import Foundation

public enum ReminderPlanner {
    public static func isQuiet(_ date: Date, settings: WellbeingSettings, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let start = settings.quietStartHour, end = settings.quietEndHour
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// When the next water reminder is due. It waits `reminderMinutes` after the last drink
    /// (or after `now` when nothing has been logged), skips quiet hours, and stays silent for
    /// the rest of a day once the goal is met. `notBefore` pushes it later (after a reminder fires or is snoozed).
    public static func next(now: Date, data: WellbeingData, notBefore: Date? = nil,
                            calendar: Calendar = .current) -> Date? {
        let settings = data.settings
        guard settings.remindersEnabled else { return nil }
        let interval = TimeInterval(max(15, settings.reminderMinutes) * 60)
        var candidate = (data.lastDrink(on: now, calendar: calendar) ?? now).addingTimeInterval(interval)
        if candidate < now { candidate = now }
        if let notBefore, candidate < notBefore { candidate = notBefore }

        for _ in 0..<6 {
            if isQuiet(candidate, settings: settings, calendar: calendar) || data.goalMet(on: candidate, calendar: calendar) {
                guard let morning = calendar.nextDate(
                    after: candidate, matching: DateComponents(hour: settings.quietEndHour, minute: 0),
                    matchingPolicy: .nextTime) else { return nil }
                candidate = morning
                continue
            }
            return candidate
        }
        return nil
    }
}
