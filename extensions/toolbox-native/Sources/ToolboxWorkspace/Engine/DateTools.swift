import Foundation

actor DateTools {
    private var stopwatchStarted: Date?

    func run(_ request: ToolRequest) throws -> ToolOutput {
        switch request.toolID {
        case "date.unix":
            return try ToolOutput(unix(request))
        case "date.epoch":
            return try ToolOutput(epoch(request))
        case "date.relative":
            return try ToolOutput(relative(request))
        case "date.timezone":
            return try ToolOutput(timezone(request))
        case "date.cronBuilder":
            return ToolOutput(cronBuilder(request))
        case "date.cronTester":
            return try ToolOutput(cronTester(request))
        case "date.rrule":
            return ToolOutput(rrule(request))
        case "date.business":
            return try ToolOutput(businessDays(request))
        case "date.iso8601":
            return ToolOutput(isoValidate(request.primary))
        case "date.duration":
            return try ToolOutput(duration(request))
        case "date.calendarDiff":
            return try ToolOutput(calendarDiff(request))
        case "date.stopwatch":
            return ToolOutput(stopwatch(request))
        case "date.countdown":
            return try ToolOutput(countdown(request))
        case "date.leap":
            return ToolOutput(leap(request.primary))
        case "date.format":
            return try ToolOutput(format(request))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func parseDate(_ text: String) throws -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Date() }
        if let value = Double(trimmed) {
            if value > 1_000_000_000_000 { return Date(timeIntervalSince1970: value / 1000) }
            return Date(timeIntervalSince1970: value)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: trimmed) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        throw ToolError.invalidInput("Could not parse date: \(trimmed)")
    }

    private func unix(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "to-date").lowercased()
        let tz = TimeZone(identifier: request.options["timezone"] ?? TimeZone.current.identifier)
            ?? .current
        if mode.contains("to-unix") || mode == "encode" {
            let date = try parseDate(request.primary)
            return String(Int(date.timeIntervalSince1970))
        }
        let date = try parseDate(request.primary)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = tz
        formatter.formatOptions = [.withInternetDateTime]
        return [
            "unix: \(Int(date.timeIntervalSince1970))",
            "iso: \(formatter.string(from: date))",
            "timezone: \(tz.identifier)",
        ].joined(separator: "\n")
    }

    private func epoch(_ request: ToolRequest) throws -> String {
        let unit = (request.options["unit"] ?? "ms").lowercased()
        let tz = TimeZone(identifier: request.options["timezone"] ?? TimeZone.current.identifier)
            ?? .current
        let value = Double(request.primary.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? Date().timeIntervalSince1970 * 1000
        let seconds: Double
        switch unit {
        case "s", "sec", "seconds": seconds = value
        case "us", "µs", "micros": seconds = value / 1_000_000
        case "ns", "nanos": seconds = value / 1_000_000_000
        default: seconds = value / 1000
        }
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = tz
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let local = DateFormatter()
        local.timeZone = tz
        local.dateStyle = .full
        local.timeStyle = .full
        return [
            "seconds: \(seconds)",
            "iso: \(formatter.string(from: date))",
            "local (\(tz.identifier)): \(local.string(from: date))",
        ].joined(separator: "\n")
    }

    private func relative(_ request: ToolRequest) throws -> String {
        let date = try parseDate(request.primary)
        let amount = Int(request.options["amount"] ?? "1") ?? 1
        let unit = (request.options["unit"] ?? "day").lowercased()
        var components = DateComponents()
        switch unit {
        case "second", "seconds": components.second = amount
        case "minute", "minutes": components.minute = amount
        case "hour", "hours": components.hour = amount
        case "week", "weeks": components.day = amount * 7
        case "month", "months": components.month = amount
        case "year", "years": components.year = amount
        default: components.day = amount
        }
        guard let result = Calendar.current.date(byAdding: components, to: date) else {
            throw ToolError.failed("Could not compute relative date.")
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: result)
    }

    private func timezone(_ request: ToolRequest) throws -> String {
        let date = try parseDate(request.primary)
        let from = TimeZone(identifier: request.options["from"] ?? TimeZone.current.identifier) ?? .current
        let to = TimeZone(identifier: request.options["to"] ?? "UTC") ?? .gmt
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        formatter.timeZone = from
        let source = formatter.string(from: date)
        formatter.timeZone = to
        let dest = formatter.string(from: date)
        return "from (\(from.identifier)): \(source)\nto (\(to.identifier)): \(dest)"
    }

    private func cronBuilder(_ request: ToolRequest) -> String {
        let minute = request.options["minute"] ?? "*/5"
        let hour = request.options["hour"] ?? "*"
        let dom = request.options["dom"] ?? "*"
        let month = request.options["month"] ?? "*"
        let dow = request.options["dow"] ?? "*"
        return "\(minute) \(hour) \(dom) \(month) \(dow)"
    }

    private func cronTester(_ request: ToolRequest) throws -> String {
        let expression = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = expression.split(separator: " ").map(String.init)
        guard parts.count == 5 else {
            throw ToolError.invalidInput("Expected 5-field cron: min hour dom month dow")
        }
        var date = try parseDate(request.secondary.isEmpty ? ISO8601DateFormatter().string(from: Date()) : request.secondary)
        var hits: [String] = []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        for _ in 0..<40_000 {
            date = date.addingTimeInterval(60)
            if matchesCron(date, parts) {
                hits.append(formatter.string(from: date))
                if hits.count == 10 { break }
            }
        }
        return hits.isEmpty ? "No matches in the next ~28 days." : hits.joined(separator: "\n")
    }

    private func matchesCron(_ date: Date, _ parts: [String]) -> Bool {
        let calendar = Calendar.current
        let values = [
            calendar.component(.minute, from: date),
            calendar.component(.hour, from: date),
            calendar.component(.day, from: date),
            calendar.component(.month, from: date),
            calendar.component(.weekday, from: date) - 1,
        ]
        for (part, value) in zip(parts, values) {
            if !cronField(part, matches: value) { return false }
        }
        return true
    }

    private func cronField(_ field: String, matches value: Int) -> Bool {
        if field == "*" { return true }
        if field.contains("/") {
            let pieces = field.split(separator: "/")
            let step = Int(pieces.last ?? "1") ?? 1
            if pieces[0] == "*" { return value % step == 0 }
        }
        if field.contains(",") {
            return field.split(separator: ",").contains { cronField(String($0), matches: value) }
        }
        if field.contains("-") {
            let pieces = field.split(separator: "-")
            guard pieces.count == 2, let lo = Int(pieces[0]), let hi = Int(pieces[1]) else { return false }
            return (lo...hi).contains(value)
        }
        return Int(field) == value
    }

    private func rrule(_ request: ToolRequest) -> String {
        let freq = (request.options["freq"] ?? "WEEKLY").uppercased()
        let interval = request.options["interval"] ?? "1"
        let count = request.options["count"] ?? "10"
        return "RRULE:FREQ=\(freq);INTERVAL=\(interval);COUNT=\(count)"
    }

    private func businessDays(_ request: ToolRequest) throws -> String {
        var date = try parseDate(request.primary)
        var remaining = Int(request.options["days"] ?? "1") ?? 1
        let step = remaining >= 0 ? 1 : -1
        remaining = abs(remaining)
        while remaining > 0 {
            date = Calendar.current.date(byAdding: .day, value: step, to: date) ?? date
            let weekday = Calendar.current.component(.weekday, from: date)
            if weekday != 1 && weekday != 7 { remaining -= 1 }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func isoValidate(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if iso.date(from: value) != nil { return "\(value): valid" }
            iso.formatOptions = [.withInternetDateTime]
            if iso.date(from: value) != nil { return "\(value): valid" }
            iso.formatOptions = [.withFullDate]
            if iso.date(from: value) != nil { return "\(value): valid (date only)" }
            return "\(value): invalid"
        }.joined(separator: "\n")
    }

    private func duration(_ request: ToolRequest) throws -> String {
        let start = try parseDate(request.primary)
        let end = try parseDate(request.secondary)
        let seconds = end.timeIntervalSince(start)
        let absSeconds = abs(seconds)
        let days = Int(absSeconds) / 86_400
        let hours = (Int(absSeconds) % 86_400) / 3_600
        let minutes = (Int(absSeconds) % 3_600) / 60
        let secs = Int(absSeconds) % 60
        return [
            "seconds: \(seconds)",
            "human: \(days)d \(hours)h \(minutes)m \(secs)s",
            seconds < 0 ? "direction: end is before start" : "direction: forward",
        ].joined(separator: "\n")
    }

    private func calendarDiff(_ request: ToolRequest) throws -> String {
        let start = try parseDate(request.primary)
        let end = try parseDate(request.secondary)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: start,
            to: end
        )
        return [
            "years: \(components.year ?? 0)",
            "months: \(components.month ?? 0)",
            "days: \(components.day ?? 0)",
            "hours: \(components.hour ?? 0)",
            "minutes: \(components.minute ?? 0)",
            "seconds: \(components.second ?? 0)",
        ].joined(separator: "\n")
    }

    private func stopwatch(_ request: ToolRequest) -> String {
        let action = (request.options["action"] ?? request.primary).lowercased()
        if action.contains("start") || action.contains("reset") {
            stopwatchStarted = Date()
            return "Stopwatch started."
        }
        guard let started = stopwatchStarted else {
            stopwatchStarted = Date()
            return "Stopwatch started."
        }
        let elapsed = Date().timeIntervalSince(started)
        return String(format: "elapsed: %.3fs", elapsed)
    }

    private func countdown(_ request: ToolRequest) throws -> String {
        let targetText = request.options["target"]?.isEmpty == false
            ? request.options["target"]!
            : request.primary
        let target = try parseDate(targetText)
        let remaining = target.timeIntervalSinceNow
        if remaining <= 0 { return "Countdown finished (\(Int(-remaining))s ago)." }
        let days = Int(remaining) / 86_400
        let hours = (Int(remaining) % 86_400) / 3_600
        let minutes = (Int(remaining) % 3_600) / 60
        let seconds = Int(remaining) % 60
        return "\(days)d \(hours)h \(minutes)m \(seconds)s remaining"
    }

    private func leap(_ text: String) -> String {
        let year = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? Calendar.current.component(.year, from: Date())
        let leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
        return "\(year): \(leap ? "leap year" : "not a leap year")"
    }

    private func format(_ request: ToolRequest) throws -> String {
        let date = try parseDate(request.primary)
        let pattern = request.options["format"] ?? "yyyy-MM-dd HH:mm:ss"
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        if let tz = request.options["timezone"], let zone = TimeZone(identifier: tz) {
            formatter.timeZone = zone
        }
        return formatter.string(from: date)
    }
}
