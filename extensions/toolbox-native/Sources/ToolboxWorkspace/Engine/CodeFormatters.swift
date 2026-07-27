import Foundation

enum CodeFormatters {
    static func sql(_ text: String) -> String {
        let keywords = Set([
            "select", "from", "where", "and", "or", "insert", "into", "values", "update", "set",
            "delete", "create", "table", "index", "drop", "alter", "join", "left", "right", "inner",
            "outer", "on", "group", "by", "order", "having", "limit", "offset", "as", "distinct",
            "union", "all", "case", "when", "then", "else", "end", "not", "null", "is", "in",
            "exists", "between", "like", "with", "primary", "key", "foreign", "references",
            "constraint", "default", "unique", "check", "asc", "desc", "inner", "cross",
        ])
        var tokens: [String] = []
        var current = ""
        var inString: Character?
        for character in text {
            if let quote = inString {
                current.append(character)
                if character == quote { inString = nil }
                continue
            }
            if character == "'" || character == "\"" {
                if !current.isEmpty { tokens.append(current); current = "" }
                inString = character
                current.append(character)
                continue
            }
            if "(),;".contains(character) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
                continue
            }
            if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { tokens.append(current) }

        var lines: [String] = []
        var line = ""
        var indent = 0
        func flush() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                lines.append(String(repeating: "  ", count: max(0, indent)) + trimmed)
            }
            line = ""
        }
        for token in tokens {
            let lower = token.lowercased()
            if ["select", "from", "where", "group", "order", "having", "limit", "offset", "union", "set", "values"].contains(lower) {
                flush()
                if lower == "select" { indent = 0 }
                line = keywords.contains(lower) ? lower.uppercased() : token
                if ["from", "where", "group", "order", "having", "limit", "union", "set", "values"].contains(lower) {
                    // keep same level
                }
                continue
            }
            if token == "(" {
                line += (line.isEmpty ? "" : " ") + "("
                flush()
                indent += 1
                continue
            }
            if token == ")" {
                flush()
                indent = max(0, indent - 1)
                line = ")"
                continue
            }
            if token == "," {
                line += ","
                flush()
                continue
            }
            if token == ";" {
                line += ";"
                flush()
                indent = 0
                continue
            }
            let word = keywords.contains(lower) ? lower.uppercased() : token
            line += (line.isEmpty ? "" : " ") + word
        }
        flush()
        return lines.joined(separator: "\n")
    }

    static func html(_ text: String) -> String {
        indentMarkup(text, voidTags: [
            "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
        ])
    }

    static func xml(_ text: String) -> String {
        indentMarkup(text, voidTags: [])
    }

    static func css(_ text: String) -> String {
        var out = ""
        var indent = 0
        var i = text.startIndex
        var inString: Character?
        while i < text.endIndex {
            let c = text[i]
            if let quote = inString {
                out.append(c)
                if c == quote { inString = nil }
                i = text.index(after: i)
                continue
            }
            if c == "\"" || c == "'" {
                inString = c
                out.append(c)
            } else if c == "{" {
                out.append(" {\n")
                indent += 1
                out.append(String(repeating: "  ", count: indent))
            } else if c == "}" {
                indent = max(0, indent - 1)
                if out.hasSuffix("  ") {
                    out.removeLast(2)
                }
                if !out.hasSuffix("\n") { out.append("\n") }
                out.append(String(repeating: "  ", count: indent))
                out.append("}\n")
                out.append(String(repeating: "  ", count: indent))
            } else if c == ";" {
                out.append(";\n")
                out.append(String(repeating: "  ", count: indent))
            } else if c.isNewline {
                // skip raw newlines; we control them
            } else {
                out.append(c)
            }
            i = text.index(after: i)
        }
        return out
            .replacingOccurrences(of: "[ \t]+\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func yaml(_ text: String) -> String {
        // Normalize indentation to 2 spaces and trim trailing spaces.
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { line -> String in
                var value = String(line)
                while value.hasPrefix("\t") {
                    value = "  " + value.dropFirst()
                }
                return value.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    static func generic(_ text: String, language: String) -> String {
        switch language.lowercased() {
        case "sql": return sql(text)
        case "html": return html(text)
        case "xml": return xml(text)
        case "css": return css(text)
        case "yaml", "yml": return yaml(text)
        case "json":
            return (try? JSONValue.parse(text).encode(pretty: true)) ?? text
        default:
            return text
                .replacingOccurrences(of: "\t", with: "    ")
                .replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
        }
    }

    static func highlight(_ text: String, language: String) -> String {
        CodeSyntax.highlight(text, language: language).text
    }

    static func astOutline(_ text: String, language: String) -> String {
        CodeSyntax.astOutline(text, language: language)
    }

    private static func indentMarkup(_ text: String, voidTags: Set<String>) -> String {
        let pattern = #"<(/)?([A-Za-z0-9:_-]+)([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output: [String] = []
        var indent = 0
        var cursor = text.startIndex
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let full = Range(match.range, in: text),
                  let closeRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text)
            else { continue }
            let before = text[cursor..<full.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                output.append(String(repeating: "  ", count: indent) + before)
            }
            let closing = !text[closeRange].isEmpty
            let name = String(text[nameRange]).lowercased()
            let tag = String(text[full])
            let selfClosing = tag.hasSuffix("/>") || voidTags.contains(name)
            if closing {
                indent = max(0, indent - 1)
                output.append(String(repeating: "  ", count: indent) + tag)
            } else {
                output.append(String(repeating: "  ", count: indent) + tag)
                if !selfClosing { indent += 1 }
            }
            cursor = full.upperBound
        }
        let tail = text[cursor...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            output.append(String(repeating: "  ", count: indent) + tail)
        }
        return output.joined(separator: "\n")
    }
}
