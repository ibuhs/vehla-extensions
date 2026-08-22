import Foundation

enum MarkdownQuickError: LocalizedError, Equatable {
    case emptySelection
    case noTables
    case noLinks
    case noHeadings
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select some Markdown first."
        case .noTables:
            return "No Markdown table was found in the selection."
        case .noLinks:
            return "No Markdown links were found in the selection."
        case .noHeadings:
            return "No headings were found in the selection."
        case .unknownAction(let id):
            return "Unknown Markdown Quick action “\(id)”."
        }
    }
}

struct MarkdownLink: Equatable, Sendable {
    let label: String
    let url: String
}

struct MarkdownHeading: Equatable, Sendable {
    let level: Int
    let text: String
}

enum MarkdownEngine {
    static func normalize(_ text: String) throws -> String {
        let source = try nonempty(text)
        var lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var inFence = false
        lines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
                || line.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
                inFence.toggle()
                return line.trimmingCharacters(in: .whitespaces)
            }
            guard !inFence else { return line }
            var next = line.replacingOccurrences(
                of: #"[ \t]+$"#,
                with: "",
                options: .regularExpression
            )
            if let match = next.prefixMatch(of: /^(#{1,6})(\s*)(.+)$/) {
                next = "\(match.1) \(match.3.trimmingCharacters(in: .whitespaces))"
            }
            return next
        }

        var collapsed: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun <= 1 { collapsed.append(line) }
            } else {
                blankRun = 0
                collapsed.append(line)
            }
        }
        while collapsed.first?.isEmpty == true { collapsed.removeFirst() }
        while collapsed.last?.isEmpty == true { collapsed.removeLast() }
        return collapsed.joined(separator: "\n")
    }

    static func strip(_ text: String) throws -> String {
        var source = try nonempty(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        source = stripFencedCode(source)
        source = replaceAll(source, /!\[([^\]]*)\]\([^)]+\)/) { String($0.1) }
        source = replaceAll(source, /\[([^\]]+)\]\([^)]+\)/) { String($0.1) }
        source = replaceAll(source, /\[([^\]]+)\]\[[^\]]*\]/) { String($0.1) }
        source = replaceAll(source, /<((?:https?:\/\/|mailto:)[^>]+)>/) { String($0.1) }
        source = replaceAll(source, /`([^`]+)`/) { String($0.1) }
        source = source.replacingOccurrences(of: "**", with: "")
        source = source.replacingOccurrences(of: "__", with: "")
        source = source.replacingOccurrences(of: "~~", with: "")
        source = replaceAll(source, /[*_]([^*_\n]+)[*_]/) { String($0.1) }
        source = source.replacingOccurrences(
            of: #"</?[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
            var next = String(line)
            if next.range(of: #"^\s{0,3}\[[^\]]+\]:\s+\S+"#, options: .regularExpression) != nil {
                return nil
            }
            next = next.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            next = next.replacingOccurrences(of: #"^\s{0,3}>\s?"#, with: "", options: .regularExpression)
            next = next.replacingOccurrences(of: #"^\s{0,3}(?:[-+*]|\d+\.)\s+"#, with: "", options: .regularExpression)
            next = next.replacingOccurrences(
                of: #"^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$"#,
                with: "",
                options: .regularExpression
            )
            if next.contains("|"), next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                next = next
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.allSatisfy { $0 == "-" || $0 == ":" } }
                    .joined(separator: " ")
            }
            return next.trimmingCharacters(in: .whitespaces)
        }

        return lines
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formatTables(_ text: String) throws -> String {
        let source = try nonempty(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var index = 0
        var found = false

        while index < lines.count {
            if let table = readTable(in: lines, at: index) {
                found = true
                output.append(contentsOf: format(table))
                index += table.count
            } else {
                output.append(lines[index])
                index += 1
            }
        }

        guard found else { throw MarkdownQuickError.noTables }
        return output.joined(separator: "\n")
    }

    static func unwrapLinks(_ text: String) throws -> String {
        let source = try nonempty(text)
        let links = extractLinks(source)
        guard !links.isEmpty else { throw MarkdownQuickError.noLinks }
        var output = source
        output = replaceAll(output, /!\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) { String($0.1) }
        output = replaceAll(output, /\[[^\]]+\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) { String($0.1) }
        output = replaceAll(output, /<((?:https?:\/\/|mailto:)[^>]+)>/) { String($0.1) }
        return output
    }

    static func extractLinks(_ text: String) -> [MarkdownLink] {
        var links: [MarkdownLink] = []
        var seen = Set<String>()

        func append(label: String, url: String) {
            let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedURL.isEmpty, seen.insert(trimmedURL).inserted else { return }
            links.append(MarkdownLink(label: label, url: trimmedURL))
        }

        for match in text.matches(of: /\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) {
            append(label: String(match.1), url: String(match.2))
        }
        for match in text.matches(of: /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/) {
            append(label: String(match.1).isEmpty ? "image" : String(match.1), url: String(match.2))
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = String(line).prefixMatch(of: /^\s{0,3}\[([^\]]+)\]:\s+(\S+)/) {
                append(label: String(match.1), url: String(match.2))
            }
        }
        for match in text.matches(of: /<((?:https?:\/\/|mailto:)[^>]+)>/) {
            append(label: String(match.1), url: String(match.1))
        }
        return links
    }

    static func renderLinks(_ text: String) throws -> String {
        let links = extractLinks(try nonempty(text))
        guard !links.isEmpty else { throw MarkdownQuickError.noLinks }
        return links.map { link in
            link.label == link.url ? link.url : "\(link.label) — \(link.url)"
        }
        .joined(separator: "\n")
    }

    static func extractHeadings(_ text: String) -> [MarkdownHeading] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line in
                guard let match = String(line).prefixMatch(of: /^(#{1,6})\s+(.+?)\s*$/) else {
                    return nil
                }
                return MarkdownHeading(
                    level: match.1.count,
                    text: String(match.2).trimmingCharacters(in: .whitespaces)
                )
            }
    }

    static func renderHeadings(_ text: String) throws -> String {
        let headings = extractHeadings(try nonempty(text))
        guard !headings.isEmpty else { throw MarkdownQuickError.noHeadings }
        return headings.map { heading in
            String(repeating: "  ", count: max(heading.level - 1, 0)) + heading.text
        }
        .joined(separator: "\n")
    }

    private static func stripFencedCode(_ text: String) -> String {
        var output: [String] = []
        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            output.append(String(line))
        }
        return output.joined(separator: "\n")
    }

    private static func nonempty(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MarkdownQuickError.emptySelection }
        return text
    }

    private static func replaceAll<Output>(
        _ text: String,
        _ regex: Regex<Output>,
        transform: (Regex<Output>.Match) -> String
    ) -> String {
        var output = ""
        var current = text.startIndex
        for match in text.matches(of: regex) {
            output += text[current..<match.range.lowerBound]
            output += transform(match)
            current = match.range.upperBound
        }
        output += text[current...]
        return output
    }

    private static func readTable(in lines: [String], at start: Int) -> [[String]]? {
        guard start + 1 < lines.count,
              isTableRow(lines[start]),
              isSeparatorRow(lines[start + 1]) else {
            return nil
        }
        var rows: [[String]] = [cells(in: lines[start])]
        let columns = rows[0].count
        guard cells(in: lines[start + 1]).count == columns else { return nil }
        rows.append(cells(in: lines[start + 1]))
        var index = start + 2
        while index < lines.count, isTableRow(lines[index]), !isSeparatorRow(lines[index]) {
            var row = cells(in: lines[index])
            if row.count < columns {
                row.append(contentsOf: Array(repeating: "", count: columns - row.count))
            } else if row.count > columns {
                row = Array(row.prefix(columns))
            }
            rows.append(row)
            index += 1
        }
        return rows.count >= 2 ? rows : nil
    }

    private static func format(_ rows: [[String]]) -> [String] {
        let columns = rows[0].count
        var widths = Array(repeating: 0, count: columns)
        for (index, row) in rows.enumerated() where index != 1 {
            for column in 0..<columns {
                widths[column] = max(widths[column], row[column].count)
            }
        }
        for column in 0..<columns {
            widths[column] = max(widths[column], 3)
        }

        return rows.enumerated().map { index, row in
            if index == 1 {
                let separators = (0..<columns).map { String(repeating: "-", count: widths[$0]) }
                return "| \(separators.joined(separator: " | ")) |"
            }
            let padded = row.enumerated().map { column, cell in
                cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            return "| \(padded.joined(separator: " | ")) |"
        }
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && !trimmed.isEmpty
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let parts = cells(in: line)
        return !parts.isEmpty && parts.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func cells(in line: String) -> [String] {
        var parts = line
            .trimmingCharacters(in: .whitespaces)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }
}
