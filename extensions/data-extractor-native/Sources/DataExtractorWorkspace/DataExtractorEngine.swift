import Foundation

enum DataExtractorError: LocalizedError, Equatable {
    case emptySelection
    case noneFound
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select some text first."
        case .noneFound:
            return "Nothing to extract was found in the selection."
        case .unknownAction(let id):
            return "Unknown Data Extractor action “\(id)”."
        }
    }
}

struct ExtractedItem: Equatable, Sendable {
    let type: String
    let value: String
}

enum DataExtractorEngine {
    static func emails(_ text: String) throws -> String {
        try joined(extractEmails(try nonempty(text)))
    }

    static func phones(_ text: String) throws -> String {
        try joined(extractPhones(try nonempty(text)))
    }

    static func ips(_ text: String) throws -> String {
        try joined(extractIPs(try nonempty(text)))
    }

    static func mentions(_ text: String) throws -> String {
        try joined(extractMentions(try nonempty(text)))
    }

    static func hashtags(_ text: String) throws -> String {
        try joined(extractHashtags(try nonempty(text)))
    }

    static func all(_ text: String) throws -> String {
        let groups = try groupedItems(in: text)
        return groups
            .map { type, values in
                ([type.capitalized] + values).joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }

    static func csv(_ text: String) throws -> String {
        let items = extractAll(try nonempty(text))
        guard !items.isEmpty else { throw DataExtractorError.noneFound }
        let rows = items.map { item in
            "\(item.type),\(csvEscape(item.value))"
        }
        return (["type,value"] + rows).joined(separator: "\n")
    }

    static func extractEmails(_ text: String) -> [String] {
        unique(text.matches(of: /(?i)[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/).map {
            String($0.0)
        })
    }

    static func extractPhones(_ text: String) -> [String] {
        unique(text.matches(of: /(?:\+\d[\d\s().-]{8,}\d|\(?\d{3}\)?[\s.-]\d{3}[\s.-]\d{4})/).compactMap { match in
            let value = String(match.0).trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = value.filter(\.isNumber)
            guard (10...15).contains(digits.count) else { return nil }
            return value
        })
    }

    static func extractIPs(_ text: String) -> [String] {
        var found: [String] = []
        for match in text.matches(of: /\b\d{1,3}(?:\.\d{1,3}){3}\b/) {
            let value = String(match.0)
            if isIPv4(value) { found.append(value) }
        }
        for match in text.matches(of: /(?:[A-Fa-f0-9]{1,4}:){1,7}:[A-Fa-f0-9]{0,4}|(?:[A-Fa-f0-9]{1,4}:){7}[A-Fa-f0-9]{1,4}|::(?:[A-Fa-f0-9]{1,4}:){0,6}[A-Fa-f0-9]{1,4}/) {
            let value = String(match.0)
            if isIPv6(value) { found.append(value) }
        }
        return unique(found)
    }

    static func extractMentions(_ text: String) -> [String] {
        unique(text.matches(of: /@[A-Za-z0-9_]+/).compactMap { match in
            guard isBoundary(before: match.range.lowerBound, in: text) else { return nil }
            return String(match.0)
        })
    }

    static func extractHashtags(_ text: String) -> [String] {
        unique(text.matches(of: /#[A-Za-z0-9_]+/).compactMap { match in
            guard isBoundary(before: match.range.lowerBound, in: text) else { return nil }
            return String(match.0)
        })
    }

    static func extractAll(_ text: String) -> [ExtractedItem] {
        var items: [ExtractedItem] = []
        items += extractEmails(text).map { ExtractedItem(type: "email", value: $0) }
        items += extractPhones(text).map { ExtractedItem(type: "phone", value: $0) }
        items += extractIPs(text).map { ExtractedItem(type: "ip", value: $0) }
        items += extractMentions(text).map { ExtractedItem(type: "mention", value: $0) }
        items += extractHashtags(text).map { ExtractedItem(type: "hashtag", value: $0) }
        return items
    }

    private static func groupedItems(in text: String) throws -> [(String, [String])] {
        let source = try nonempty(text)
        let groups: [(String, [String])] = [
            ("emails", extractEmails(source)),
            ("phones", extractPhones(source)),
            ("ips", extractIPs(source)),
            ("mentions", extractMentions(source)),
            ("hashtags", extractHashtags(source)),
        ]
        let present = groups.filter { !$0.1.isEmpty }
        guard !present.isEmpty else { throw DataExtractorError.noneFound }
        return present
    }

    private static func nonempty(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DataExtractorError.emptySelection
        }
        return text
    }

    private static func joined(_ values: [String]) throws -> String {
        guard !values.isEmpty else { throw DataExtractorError.noneFound }
        return values.joined(separator: "\n")
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            let key = value.lowercased()
            return seen.insert(key).inserted
        }
    }

    private static func isBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !previous.isLetter && !previous.isNumber
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), (0...255).contains(number) else { return false }
            return String(number) == part || part == "0"
        }
    }

    private static func isIPv6(_ value: String) -> Bool {
        guard value.contains(":") else { return false }
        let compressed = value.contains("::")
        if compressed, value.components(separatedBy: "::").count != 2 {
            return false
        }
        let groups = value.split(separator: ":", omittingEmptySubsequences: true)
        let allowed = compressed ? 1...7 : 8...8
        guard allowed.contains(groups.count) else { return false }
        return groups.allSatisfy { group in
            (1...4).contains(group.count) && group.allSatisfy(\.isHexDigit)
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
