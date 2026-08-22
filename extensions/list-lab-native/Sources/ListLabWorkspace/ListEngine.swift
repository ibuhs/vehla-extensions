import Foundation

enum ListLabError: LocalizedError, Equatable {
    case emptySelection
    case noItems
    case needTwoLines
    case emptyClipboard
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select a list first."
        case .noItems:
            return "No list items were found in the selection."
        case .needTwoLines:
            return "Select at least two lines to shuffle."
        case .emptyClipboard:
            return "Copy a prefix first."
        case .unknownAction(let id):
            return "Unknown List Lab action “\(id)”."
        }
    }
}

enum ListEngine {
    static func split(_ text: String, separator: Character) throws -> String {
        let pieces = try items(from: text).flatMap { line -> [String] in
            guard line.contains(separator) else { return [line] }
            return line
                .split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        guard !pieces.isEmpty else { throw ListLabError.noItems }
        return pieces.joined(separator: "\n")
    }

    static func join(_ text: String, separator: String) throws -> String {
        let pieces = try items(from: text)
        return pieces.joined(separator: separator)
    }

    static func shuffle(_ text: String) throws -> String {
        var generator = SystemRandomNumberGenerator()
        return try shuffle(text, using: &generator)
    }

    static func shuffle<G: RandomNumberGenerator>(
        _ text: String,
        using generator: inout G
    ) throws -> String {
        var pieces = try items(from: text)
        guard pieces.count >= 2 else { throw ListLabError.needTwoLines }
        pieces.shuffle(using: &generator)
        return pieces.joined(separator: "\n")
    }

    static func number(_ text: String) throws -> String {
        try items(from: text)
            .map(stripLeadingNumber)
            .enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    static func quote(_ text: String) throws -> String {
        try items(from: text)
            .map { wrap($0, left: "\"", right: "\"") }
            .joined(separator: "\n")
    }

    static func wrapParens(_ text: String) throws -> String {
        try items(from: text)
            .map { wrap($0, left: "(", right: ")") }
            .joined(separator: "\n")
    }

    static func unwrap(_ text: String) throws -> String {
        let source = try nonempty(text)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if let inner = unwrapOnce(trimmed),
           (try? items(from: source).count) ?? 0 <= 1 || inner.contains("\n") {
            let result = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else { throw ListLabError.noItems }
            return result
        }

        let lines = normalizedLines(source).map { line -> String in
            let item = line.trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { return line }
            return unwrapOnce(item) ?? item
        }
        let result = lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw ListLabError.noItems }
        return result
    }

    static func prefix(_ text: String, with prefix: String) throws -> String {
        let trimmedPrefix = prefix
        guard !trimmedPrefix.isEmpty else { throw ListLabError.emptyClipboard }
        return try items(from: text)
            .map { trimmedPrefix + $0 }
            .joined(separator: "\n")
    }

    static func items(from text: String) throws -> [String] {
        let pieces = normalizedLines(try nonempty(text))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { throw ListLabError.noItems }
        return pieces
    }

    private static func nonempty(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ListLabError.emptySelection
        }
        return text
    }

    private static func normalizedLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func stripLeadingNumber(_ line: String) -> String {
        guard let match = line.prefixMatch(of: /^\d+\.\s+/) else { return line }
        return String(line[match.range.upperBound...])
    }

    private static func wrap(_ text: String, left: String, right: String) -> String {
        if isWrapped(text, left: left, right: right) { return text }
        return left + text + right
    }

    private static func unwrapOnce(_ text: String) -> String? {
        let pairs = [
            ("(", ")"),
            ("[", "]"),
            ("{", "}"),
            ("\"", "\""),
            ("'", "'"),
            ("“", "”"),
            ("‘", "’"),
        ]
        for (left, right) in pairs where isWrapped(text, left: left, right: right) {
            let start = text.index(text.startIndex, offsetBy: left.count)
            let end = text.index(text.endIndex, offsetBy: -right.count)
            return String(text[start..<end])
        }
        return nil
    }

    private static func isWrapped(_ text: String, left: String, right: String) -> Bool {
        text.count >= left.count + right.count
            && text.hasPrefix(left)
            && text.hasSuffix(right)
    }
}
