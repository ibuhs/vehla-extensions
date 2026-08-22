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

struct NoteDraft: Equatable, Sendable {
    let title: String
    let body: String
    let removesFirstRenderedLine: Bool
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

    static func noteDraft(from text: String) throws -> NoteDraft {
        let source = try nonempty(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = source.components(separatedBy: "\n")
        let meaningful = lines.indices.filter {
            !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let titleIndex = meaningful.first else {
            throw CaptureHubError.emptySelection
        }
        let firstLine = lines[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)

        if meaningful.count == 1 {
            if firstLine.count <= noteTitleLimit {
                return NoteDraft(
                    title: firstLine,
                    body: "",
                    removesFirstRenderedLine: true
                )
            }
            return NoteDraft(
                title: "Vehla Capture",
                body: source,
                removesFirstRenderedLine: false
            )
        }

        let title = firstLine.count <= noteTitleLimit
            ? firstLine
            : String(firstLine.prefix(noteTitleLimit - 1)) + "…"
        let body = lines.dropFirst(titleIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        return NoteDraft(
            title: title,
            body: body,
            removesFirstRenderedLine: true
        )
    }

    static func noteTitle(from text: String) throws -> String {
        try noteDraft(from: text).title
    }

    static func noteBody(from text: String) throws -> String {
        try noteDraft(from: text).body
    }

    static func html(from text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(escapedIndentedLine)
            .joined(separator: "<br>")
    }

    static func sanitizedHTML(
        _ html: String,
        removingFirstRenderedLine: Bool
    ) -> String? {
        guard !html.isEmpty, html.utf8.count <= 1_048_576 else { return nil }
        let sanitized = HTMLSanitizer.sanitize(html)
        guard !HTMLSanitizer.plainText(in: sanitized)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return removingFirstRenderedLine
            ? HTMLSanitizer.removingFirstRenderedLine(from: sanitized)
            : sanitized
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

    private static func escapedIndentedLine(_ line: String) -> String {
        var indentation = ""
        var contentStart = line.startIndex
        while contentStart < line.endIndex {
            if line[contentStart] == " " {
                indentation += "&nbsp;"
            } else if line[contentStart] == "\t" {
                indentation += "&nbsp;&nbsp;&nbsp;&nbsp;"
            } else {
                break
            }
            contentStart = line.index(after: contentStart)
        }
        return indentation + escapeHTML(String(line[contentStart...]))
    }

    fileprivate static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
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

private enum HTMLSanitizer {
    private struct Tag {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let source: String
    }

    private enum Token {
        case text(String)
        case tag(Tag)
    }

    private static let allowedTags: Set<String> = [
        "a", "b", "blockquote", "br", "div", "em", "h1", "h2", "h3",
        "h4", "h5", "h6", "i", "li", "ol", "p", "strong", "ul",
    ]
    private static let voidTags: Set<String> = ["br"]
    private static let blockedContentTags: Set<String> = [
        "script", "style", "iframe", "object", "audio", "video",
        "svg", "math", "canvas", "template", "noscript",
    ]
    private static let discardedTags: Set<String> = [
        "img", "picture", "source", "track", "embed", "meta", "link", "base",
        "form", "input", "button", "select", "option", "textarea",
    ]
    private static let blockTags: Set<String> = [
        "blockquote", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "p",
    ]

    static func sanitize(_ source: String) -> String {
        var output = ""
        var openTags: [String] = []
        var suppressed: [String] = []

        for token in tokenize(source) {
            switch token {
            case .text(let text):
                if suppressed.isEmpty {
                    output += text
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: ">", with: "&gt;")
                }
            case .tag(let tag):
                if !suppressed.isEmpty {
                    if tag.isClosing, tag.name == suppressed.last {
                        suppressed.removeLast()
                    } else if !tag.isClosing,
                              !tag.isSelfClosing,
                              blockedContentTags.contains(tag.name) {
                        suppressed.append(tag.name)
                    }
                    continue
                }
                if blockedContentTags.contains(tag.name) {
                    if !tag.isClosing, !tag.isSelfClosing {
                        suppressed.append(tag.name)
                    }
                    continue
                }
                if discardedTags.contains(tag.name) || !allowedTags.contains(tag.name) {
                    continue
                }
                if tag.name == "br" {
                    if !tag.isClosing {
                        output += "<br>"
                    }
                    continue
                }
                if tag.isClosing {
                    guard let index = openTags.lastIndex(of: tag.name) else { continue }
                    for name in openTags[index...].reversed() {
                        output += "</\(name)>"
                    }
                    openTags.removeSubrange(index...)
                    continue
                }
                if tag.name == "a", let href = safeHref(in: tag.source) {
                    output += "<a href=\"\(CaptureHubEngine.escapeHTML(href))\">"
                } else {
                    output += "<\(tag.name)>"
                }
                if !tag.isSelfClosing {
                    openTags.append(tag.name)
                }
            }
        }
        for name in openTags.reversed() {
            output += "</\(name)>"
        }
        return output
    }

    static func plainText(in html: String) -> String {
        var result = ""
        for token in tokenize(html) {
            switch token {
            case .text(let text):
                result += decodeEntities(text)
            case .tag(let tag):
                if tag.name == "br" || (tag.isClosing && blockTags.contains(tag.name)) {
                    result += "\n"
                }
            }
        }
        return result
    }

    static func removingFirstRenderedLine(from html: String) -> String {
        var tokens = tokenize(html)
        guard let firstText = tokens.firstIndex(where: {
            if case .text(let text) = $0 {
                return !decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return false
        }) else {
            return ""
        }

        var stack: [(name: String, index: Int)] = []
        for index in 0...firstText {
            guard case .tag(let tag) = tokens[index] else { continue }
            if tag.isClosing {
                if let match = stack.lastIndex(where: { $0.name == tag.name }) {
                    stack.removeSubrange(match...)
                }
            } else if !tag.isSelfClosing, !voidTags.contains(tag.name) {
                stack.append((tag.name, index))
            }
        }
        let enclosing = stack.last(where: { $0.name == "li" })
            ?? stack.last(where: { blockTags.contains($0.name) })

        if let enclosing,
           let close = matchingClose(
               for: enclosing.name,
               openingAt: enclosing.index,
               in: tokens
           ) {
            if let lineBreak = (firstText..<close).first(where: {
                guard case .tag(let tag) = tokens[$0] else { return false }
                return tag.name == "br" && !tag.isClosing
            }) {
                clearText(from: enclosing.index + 1, through: lineBreak, tokens: &tokens)
                tokens.remove(at: lineBreak)
            } else {
                tokens.removeSubrange(enclosing.index...close)
            }
            return serialize(tokens)
        }

        let boundary = (firstText + 1..<tokens.count).first(where: {
            guard case .tag(let tag) = tokens[$0], !tag.isClosing else { return false }
            return tag.name == "br" || blockTags.contains(tag.name)
        })
        let end = boundary ?? tokens.count
        if firstText < end {
            clearText(from: firstText, through: end - 1, tokens: &tokens)
        }
        if let boundary,
           case .tag(let tag) = tokens[boundary],
           tag.name == "br" {
            tokens.remove(at: boundary)
        }
        return serialize(tokens)
    }

    private static func clearText(
        from start: Int,
        through end: Int,
        tokens: inout [Token]
    ) {
        guard start <= end else { return }
        for index in start...end {
            if case .text = tokens[index] {
                tokens[index] = .text("")
            }
        }
    }

    private static func matchingClose(
        for name: String,
        openingAt opening: Int,
        in tokens: [Token]
    ) -> Int? {
        var depth = 0
        for index in opening..<tokens.count {
            guard case .tag(let tag) = tokens[index], tag.name == name else { continue }
            if tag.isClosing {
                depth -= 1
                if depth == 0 { return index }
            } else if !tag.isSelfClosing {
                depth += 1
            }
        }
        return nil
    }

    private static func serialize(_ tokens: [Token]) -> String {
        tokens.map {
            switch $0 {
            case .text(let text):
                text
            case .tag(let tag):
                tag.source
            }
        }.joined()
    }

    private static func safeHref(in tag: String) -> String? {
        let pattern = #"(?is)\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: tag,
                range: NSRange(tag.startIndex..<tag.endIndex, in: tag)
              ) else {
            return nil
        }
        let encoded = (1...3).compactMap { group -> String? in
            let range = match.range(at: group)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: tag) else {
                return nil
            }
            return String(tag[swiftRange])
        }.first
        guard let encoded else { return nil }
        let href = decodeEntities(encoded)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compactScheme = href.prefix(while: { $0 != ":" })
            .filter {
                !$0.isWhitespace
                    && $0.unicodeScalars.allSatisfy { $0.value > 32 && $0.value != 127 }
            }
            .lowercased()
        guard href.contains(":"), ["http", "https", "mailto"].contains(compactScheme) else {
            return nil
        }
        return href
    }

    private static func tokenize(_ source: String) -> [Token] {
        var result: [Token] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let start = source[cursor...].firstIndex(of: "<") else {
                result.append(.text(String(source[cursor...])))
                break
            }
            if start > cursor {
                result.append(.text(String(source[cursor..<start])))
            }
            if source[start...].hasPrefix("<!--"),
               let end = source[start...].range(of: "-->")?.upperBound {
                cursor = end
                continue
            }
            guard let end = tagEnd(in: source, startingAt: start) else {
                result.append(.text(String(source[start...])))
                break
            }
            let raw = String(source[start...end])
            if let tag = parseTag(raw) {
                result.append(.tag(tag))
            }
            cursor = source.index(after: end)
        }
        return result
    }

    private static func tagEnd(in source: String, startingAt start: String.Index) -> String.Index? {
        var cursor = source.index(after: start)
        var quote: Character?
        while cursor < source.endIndex {
            let character = source[cursor]
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func parseTag(_ source: String) -> Tag? {
        var content = source.dropFirst().dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !content.hasPrefix("!") && !content.hasPrefix("?") else {
            return nil
        }
        let closing = content.hasPrefix("/")
        if closing {
            content.removeFirst()
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = content.prefix {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == ":"
        }.lowercased()
        guard !name.isEmpty else { return nil }
        return Tag(
            name: name,
            isClosing: closing,
            isSelfClosing: content.hasSuffix("/") || voidTags.contains(name),
            source: source
        )
    }

    private static func decodeEntities(_ source: String) -> String {
        var result = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard source[cursor] == "&",
                  let semicolon = source[cursor...].prefix(16).firstIndex(of: ";") else {
                result.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }
            let entityStart = source.index(after: cursor)
            let entity = String(source[entityStart..<semicolon]).lowercased()
            let scalar: UnicodeScalar?
            if entity.hasPrefix("#x") {
                scalar = UInt32(entity.dropFirst(2), radix: 16).flatMap(UnicodeScalar.init)
            } else if entity.hasPrefix("#") {
                scalar = UInt32(entity.dropFirst()).flatMap(UnicodeScalar.init)
            } else {
                scalar = [
                    "amp": "&", "apos": "'", "colon": ":", "gt": ">",
                    "lt": "<", "newline": "\n", "quot": "\"", "tab": "\t",
                ][entity]?.unicodeScalars.first
            }
            guard let scalar else {
                result.append(source[cursor])
                cursor = source.index(after: cursor)
                continue
            }
            result.unicodeScalars.append(scalar)
            cursor = source.index(after: semicolon)
        }
        return result
    }
}
