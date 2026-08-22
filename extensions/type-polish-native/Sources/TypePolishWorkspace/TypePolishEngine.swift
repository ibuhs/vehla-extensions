import Foundation

enum TypePolishError: LocalizedError, Equatable {
    case emptySelection
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select some text first."
        case .unknownAction(let id):
            return "Unknown Type Polish action “\(id)”."
        }
    }
}

enum TypePolishEngine {
    static func straightenQuotes(_ text: String) throws -> String {
        var output = try nonempty(text)
        let replacements: [(String, String)] = [
            ("“", "\""),
            ("”", "\""),
            ("„", "\""),
            ("‟", "\""),
            ("«", "\""),
            ("»", "\""),
            ("‘", "'"),
            ("’", "'"),
            ("‚", "'"),
            ("‛", "'"),
            ("‹", "'"),
            ("›", "'"),
            ("`", "'"),
            ("´", "'"),
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        return output
    }

    static func cleanDashes(_ text: String) throws -> String {
        var output = try nonempty(text)
        let replacements: [(String, String)] = [
            ("…", "..."),
            ("⋯", "..."),
            ("—", "--"),
            ("―", "--"),
            ("–", "-"),
            ("−", "-"),
            ("‐", "-"),
            ("‑", "-"),
            ("‒", "-"),
        ]
        for (from, to) in replacements {
            output = output.replacingOccurrences(of: from, with: to)
        }
        return output
    }

    static func unwrap(_ text: String) throws -> String {
        let source = normalizeNewlines(try nonempty(text))
        let paragraphs = source
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            .filter { !$0.isEmpty }
        return paragraphs.joined(separator: "\n\n")
    }

    static func collapseSpaces(_ text: String) throws -> String {
        let source = normalizeNewlines(try nonempty(text))
        let lines = source
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line -> String in
                var next = String(line)
                for space in unicodeSpaces {
                    next = next.replacingOccurrences(of: space, with: " ")
                }
                next = next.replacingOccurrences(of: "\t", with: " ")
                while next.contains("  ") {
                    next = next.replacingOccurrences(of: "  ", with: " ")
                }
                return next.trimmingCharacters(in: .whitespaces)
            }
        return collapseBlankRuns(lines).joined(separator: "\n")
    }

    static func stripJunk(_ text: String) throws -> String {
        var output = try nonempty(text)
        for mark in invisibleMarks {
            output = output.replacingOccurrences(of: mark, with: "")
        }
        output = output.replacingOccurrences(
            of: #"\{\\rtf[^}]*\}"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TypePolishError.emptySelection }
        return output
    }

    static func polish(_ text: String) throws -> String {
        var output = try nonempty(text)
        output = try stripJunk(output)
        output = try straightenQuotes(output)
        output = try cleanDashes(output)
        output = try unwrap(output)
        output = try collapseSpaces(output)
        return output
    }

    private static func nonempty(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TypePolishError.emptySelection
        }
        return text
    }

    private static func normalizeNewlines(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private static func collapseBlankRuns(_ lines: [String]) -> [String] {
        var output: [String] = []
        var blankRun = 0
        for line in lines {
            if line.isEmpty {
                blankRun += 1
                if blankRun == 1 { output.append(line) }
            } else {
                blankRun = 0
                output.append(line)
            }
        }
        while output.first?.isEmpty == true { output.removeFirst() }
        while output.last?.isEmpty == true { output.removeLast() }
        return output
    }

    private static let unicodeSpaces = [
        "\u{00A0}",
        "\u{2000}",
        "\u{2001}",
        "\u{2002}",
        "\u{2003}",
        "\u{2004}",
        "\u{2005}",
        "\u{2006}",
        "\u{2007}",
        "\u{2008}",
        "\u{2009}",
        "\u{200A}",
        "\u{202F}",
        "\u{205F}",
        "\u{3000}",
    ]

    private static let invisibleMarks = [
        "\u{00AD}",
        "\u{200B}",
        "\u{200C}",
        "\u{200D}",
        "\u{200E}",
        "\u{200F}",
        "\u{202A}",
        "\u{202B}",
        "\u{202C}",
        "\u{202D}",
        "\u{202E}",
        "\u{2060}",
        "\u{2066}",
        "\u{2067}",
        "\u{2068}",
        "\u{2069}",
        "\u{FEFF}",
        "\u{FFFC}",
    ]
}
