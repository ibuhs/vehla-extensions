import Foundation

public struct Brief: Equatable, Sendable {
    public let greeting: String
    public let sentences: [String]
    public var text: String { sentences.joined(separator: " ") }

    public init(greeting: String, sentences: [String]) {
        self.greeting = greeting
        self.sentences = sentences
    }
}

public enum BriefComposer {
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// A plain, deterministic summary of the day. Works with no network and no AI.
    public static func compose(
        now: Date, events: [CalendarItem], reminders: [ReminderItem], weather: WeatherSnapshot?,
        fahrenheit: Bool = false, calendar: Calendar = .current,
        time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> Brief {
        var sentences: [String] = []

        let timed = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let inProgress = timed.first { $0.isInProgress(at: now) }
        let upcoming = timed.filter { $0.start > now }
        if let inProgress {
            sentences.append("\(inProgress.title) is on until \(time(inProgress.end)).")
        }
        if let next = upcoming.first {
            let remaining = upcoming.count
            sentences.append(remaining == 1
                ? "Next up: \(next.title) at \(time(next.start))."
                : "\(remaining) events left today, starting with \(next.title) at \(time(next.start)).")
        } else if inProgress == nil {
            sentences.append(timed.isEmpty ? "Your calendar is clear today." : "Nothing else on your calendar today.")
        }
        if let allDay = events.first(where: \.isAllDay) { sentences.append("All day: \(allDay.title).") }

        if let weather {
            let condition = WeatherCondition.forCode(weather.code)
            var line = "\(condition.summary), \(Temperature.format(weather.temperatureC, fahrenheit: fahrenheit))"
            line += " with a high of \(Temperature.format(weather.highC, fahrenheit: fahrenheit))."
            if weather.precipitationChance >= 50 && !condition.isWet {
                line += " Rain is likely (\(weather.precipitationChance)%)."
            }
            sentences.append(line)
        }

        if !reminders.isEmpty {
            sentences.append("\(reminders.count) reminder\(reminders.count == 1 ? "" : "s") due today.")
        }

        return Brief(greeting: greeting(hour: calendar.component(.hour, from: now)), sentences: sentences)
    }

    /// The next timed event that starts within `lead` minutes (and hasn't started yet).
    public static func upcoming(_ events: [CalendarItem], now: Date, leadMinutes: Int = 10) -> CalendarItem? {
        let horizon = now.addingTimeInterval(TimeInterval(leadMinutes * 60))
        return events.filter { !$0.isAllDay && $0.start > now && $0.start <= horizon }.min { $0.start < $1.start }
    }
}
