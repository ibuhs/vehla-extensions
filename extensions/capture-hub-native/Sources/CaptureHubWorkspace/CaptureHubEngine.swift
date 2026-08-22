import Foundation

enum CaptureHubError: LocalizedError, Equatable {
    case emptySelection
    case tooManyReminderLines(Int)
    case remindersPermissionDenied
    case eventsPermissionDenied
    case noWritableReminderList
    case noWritableCalendar
    case automationDenied
    case notesFailure(String)
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            "Select some text first."
        case .tooManyReminderLines(let count):
            "The selection has \(count) non-empty lines. Capture Hub can create at most 100 reminders at once."
        case .remindersPermissionDenied:
            "Reminders access is denied. Allow Vehla in System Settings → Privacy & Security → Reminders."
        case .eventsPermissionDenied:
            "Calendar access is denied. Allow Vehla in System Settings → Privacy & Security → Calendars."
        case .noWritableReminderList:
            "No writable default reminders list is available."
        case .noWritableCalendar:
            "No writable calendar is available."
        case .automationDenied:
            "Apple Notes Automation is denied. Allow Vehla in System Settings → Privacy & Security → Automation."
        case .notesFailure(let message):
            "Apple Notes could not complete the capture: \(message)"
        case .unknownAction(let id):
            "Unknown Capture Hub action “\(id)”."
        }
    }
}

struct CaptureHubDateMatch: Equatable, Sendable {
    let range: NSRange
    let date: Date
    let duration: TimeInterval
}

struct ReminderDraft: Equatable, Sendable {
    let title: String
    let dueDate: Date?
}

struct EventDraft: Equatable, Sendable {
    let title: String
    let startDate: Date
    let endDate: Date
    let notes: String
}

enum CaptureHubEngine {
    static let reminderLimit = 100
    static let noteTitleLimit = 80

    static func detectDates(in text: String) throws -> [CaptureHubDateMatch] {
        let detector = try NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { match in
            guard let date = match.date else { return nil }
            return CaptureHubDateMatch(
                range: match.range,
                date: date,
                duration: match.duration
            )
        }
    }

    static func reminderDraft(
        from text: String,
        dateMatches: [CaptureHubDateMatch]? = nil
    ) throws -> ReminderDraft {
        let source = try nonempty(text)
        let first = try dateMatches ?? detectDates(in: source)
        let match = first.first
        let title = cleanedTitle(
            removing: match.map { [$0.range] } ?? [],
            from: source,
            fallback: "Reminder"
        )
        return ReminderDraft(title: title, dueDate: match?.date)
    }

    static func reminderLines(from text: String) throws -> [String] {
        _ = try nonempty(text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count <= reminderLimit else {
            throw CaptureHubError.tooManyReminderLines(lines.count)
        }
        return lines
    }

    static func eventDraft(
        from text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        dateMatches: [CaptureHubDateMatch]? = nil
    ) throws -> EventDraft {
        let source = try nonempty(text)
        let matches = try dateMatches ?? detectDates(in: source)
        let durationMatch = explicitDuration(in: source)
        let start = matches.first?.date ?? nextWholeHour(after: now, calendar: calendar)

        let end: Date
        if matches.count > 1, matches[1].date > start {
            end = matches[1].date
        } else if let detectedDuration = matches.first?.duration, detectedDuration > 0 {
            end = start.addingTimeInterval(detectedDuration)
        } else if let explicitDuration = durationMatch?.duration {
            end = start.addingTimeInterval(explicitDuration)
        } else {
            end = start.addingTimeInterval(60 * 60)
        }

        var removedRanges = matches.prefix(2).map(\.range)
        if let durationMatch {
            removedRanges.append(durationMatch.range)
        }
        return EventDraft(
            title: cleanedTitle(
                removing: removedRanges,
                from: source,
                fallback: "Calendar Event"
            ),
            startDate: start,
            endDate: end,
            notes: source
        )
    }

    static func noteTitle(from text: String) throws -> String {
        let source = try nonempty(text)
        let firstLine = source.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Vehla Capture"
        guard firstLine.count > noteTitleLimit else { return firstLine }
        return String(firstLine.prefix(noteTitleLimit - 1)) + "…"
    }

    static func noteBody(from text: String) throws -> String {
        let source = try nonempty(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = source.components(separatedBy: "\n")
        guard let titleIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            return ""
        }
        return lines.dropFirst(titleIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func html(from text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    static func appleScriptString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func nonempty(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureHubError.emptySelection
        }
        return text
    }

    private static func nextWholeHour(after date: Date, calendar: Calendar) -> Date {
        if let interval = calendar.dateInterval(of: .hour, for: date),
           let next = calendar.date(byAdding: .hour, value: 1, to: interval.start) {
            return next
        }
        return date.addingTimeInterval(60 * 60)
    }

    private static func explicitDuration(
        in text: String
    ) -> (range: NSRange, duration: TimeInterval)? {
        let pattern = #"(?i)\bfor\s+(\d+(?:\.\d+)?)\s*(minutes?|mins?|hours?|hrs?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else {
            return nil
        }
        let unit = text[unitRange].lowercased()
        let seconds = value * (unit.hasPrefix("h") ? 3_600 : 60)
        return (match.range, seconds)
    }

    private static func cleanedTitle(
        removing ranges: [NSRange],
        from text: String,
        fallback: String
    ) -> String {
        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard range.location != NSNotFound, NSMaxRange(range) <= mutable.length else {
                continue
            }
            mutable.replaceCharacters(in: range, with: " ")
        }
        let collapsed = (mutable as String)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n,;:-–—"))
        return collapsed.isEmpty ? fallback : collapsed
    }
}
