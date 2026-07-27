import Foundation
import Splash

enum CodeSyntax {
    static func highlight(_ text: String, language: String) -> (text: String, html: String) {
        let lang = language.lowercased()
        let annotated: String
        let bodyHTML: String
        if lang == "swift" || (lang == "auto" && looksLikeSwift(text)) {
            let highlighter = SyntaxHighlighter(format: HTMLOutputFormat())
            bodyHTML = highlighter.highlight(text)
            annotated = splashPlainAnnotation(text)
        } else {
            let tokens = tokenize(text, language: lang)
            annotated = renderAnnotated(tokens)
            bodyHTML = renderHTML(tokens)
        }
        let html = """
        <!doctype html><html><head><meta charset="utf-8"/>
        <style>
          body { margin: 0; background: #0f172a; color: #e2e8f0; font: 13px/1.45 ui-monospace, Menlo, monospace; }
          pre { margin: 0; padding: 16px; white-space: pre-wrap; }
          .keyword,.kw { color: #c084fc; font-weight: 600; }
          .string,.str { color: #86efac; }
          .number,.num { color: #fcd34d; }
          .comment,.com { color: #64748b; font-style: italic; }
          .type { color: #7dd3fc; }
          .call { color: #93c5fd; }
          .property { color: #fda4af; }
        </style></head><body><pre>\(bodyHTML)</pre></body></html>
        """
        return (annotated, html)
    }

    static func astOutline(_ text: String, language: String) -> String {
        let lang = resolvedLanguage(text, language)
        switch lang {
        case "json":
            if let value = try? JSONValue.parse(text) {
                return tree(from: value, path: "$").joined(separator: "\n")
            }
        case "swift", "js", "javascript", "ts", "typescript", "python", "java", "kotlin", "go", "rust", "c", "cpp":
            return structuralOutline(text, language: lang)
        default:
            break
        }
        return structuralOutline(text, language: lang)
    }

    private static func resolvedLanguage(_ text: String, _ language: String) -> String {
        let lang = language.lowercased()
        if lang != "auto" { return lang }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "json" }
        if looksLikeSwift(text) { return "swift" }
        if text.contains("def ") || text.contains("import ") && text.contains(":") { return "python" }
        if text.contains("function ") || text.contains("const ") || text.contains("=>") { return "javascript" }
        return "text"
    }

    private static func looksLikeSwift(_ text: String) -> Bool {
        text.contains("func ") || text.contains("let ") || text.contains("var ") || text.contains("import Foundation")
    }

    private static func splashPlainAnnotation(_ text: String) -> String {
        // Line-numbered mirror of source for the text pane.
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .enumerated()
            .map { String(format: "%4d │ %@", $0.offset + 1, String($0.element)) }
            .joined(separator: "\n")
    }

    private enum Kind { case plain, keyword, string, number, comment }

    private static func tokenize(_ text: String, language: String) -> [(String, Kind)] {
        let keywords = keywordSet(for: language)
        var tokens: [(String, Kind)] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i...].hasPrefix("//") || (language == "python" && text[i] == "#") {
                let start = i
                while i < text.endIndex, text[i] != "\n" { i = text.index(after: i) }
                tokens.append((String(text[start..<i]), .comment))
                continue
            }
            if text[i] == "\"" || text[i] == "'" {
                let quote = text[i]
                let start = i
                i = text.index(after: i)
                while i < text.endIndex {
                    if text[i] == "\\" {
                        i = text.index(after: i)
                        if i < text.endIndex { i = text.index(after: i) }
                        continue
                    }
                    if text[i] == quote {
                        i = text.index(after: i)
                        break
                    }
                    i = text.index(after: i)
                }
                tokens.append((String(text[start..<i]), .string))
                continue
            }
            if text[i].isNumber {
                let start = i
                while i < text.endIndex, text[i].isNumber || text[i] == "." { i = text.index(after: i) }
                tokens.append((String(text[start..<i]), .number))
                continue
            }
            if text[i].isLetter || text[i] == "_" {
                let start = i
                while i < text.endIndex, text[i].isLetter || text[i].isNumber || text[i] == "_" {
                    i = text.index(after: i)
                }
                let word = String(text[start..<i])
                tokens.append((word, keywords.contains(word) ? .keyword : .plain))
                continue
            }
            let start = i
            i = text.index(after: i)
            tokens.append((String(text[start..<i]), .plain))
        }
        return tokens
    }

    private static func keywordSet(for language: String) -> Set<String> {
        switch language {
        case "swift":
            return ["let", "var", "func", "return", "if", "else", "guard", "class", "struct", "enum", "import", "async", "await", "actor", "try", "throw", "throws", "protocol", "extension", "switch", "case", "default", "for", "in", "while", "nil", "true", "false", "self", "Self", "init", "deinit", "where", "some", "any"]
        case "python":
            return ["def", "return", "if", "else", "elif", "class", "import", "from", "for", "while", "with", "as", "try", "except", "yield", "async", "await", "True", "False", "None", "lambda", "pass", "raise", "in", "not", "and", "or"]
        case "js", "javascript", "ts", "typescript":
            return ["const", "let", "var", "function", "return", "if", "else", "class", "import", "export", "from", "async", "await", "try", "catch", "finally", "new", "this", "typeof", "instanceof", "switch", "case", "default", "for", "of", "in", "while", "null", "undefined", "true", "false"]
        case "sql":
            return ["select", "from", "where", "insert", "update", "delete", "join", "create", "table", "index", "into", "values", "and", "or", "not", "null", "order", "by", "group", "limit", "offset", "inner", "left", "right", "on", "as"]
        default:
            return ["if", "else", "for", "while", "return", "class", "function", "import", "const", "let", "var", "def", "true", "false", "null"]
        }
    }

    private static func renderAnnotated(_ tokens: [(String, Kind)]) -> String {
        var line = 1
        var current = ""
        var lines: [String] = []
        func flush() {
            lines.append(String(format: "%4d │ %@", line, current))
            current = ""
            line += 1
        }
        for (text, kind) in tokens {
            let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, part) in parts.enumerated() {
                let piece = String(part)
                switch kind {
                case .keyword: current += "**\(piece)**"
                case .string: current += "\"\(piece)\""
                case .comment: current += "/* \(piece) */"
                default: current += piece
                }
                if idx < parts.count - 1 { flush() }
            }
        }
        if !current.isEmpty || lines.isEmpty { flush() }
        return lines.joined(separator: "\n")
    }

    private static func renderHTML(_ tokens: [(String, Kind)]) -> String {
        tokens.map { text, kind in
            let escaped = htmlEscape(text)
            switch kind {
            case .keyword: return "<span class=\"keyword\">\(escaped)</span>"
            case .string: return "<span class=\"string\">\(escaped)</span>"
            case .number: return "<span class=\"number\">\(escaped)</span>"
            case .comment: return "<span class=\"comment\">\(escaped)</span>"
            case .plain: return escaped
            }
        }.joined()
    }

    private static func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func tree(from value: JSONValue, path: String, depth: Int = 0) -> [String] {
        let pad = String(repeating: "  ", count: depth)
        switch value {
        case .object(let pairs):
            var lines = ["\(pad)\(path) object(\(pairs.count))"]
            for (key, child) in pairs {
                lines.append(contentsOf: tree(from: child, path: "\(path).\(key)", depth: depth + 1))
            }
            return lines
        case .array(let items):
            var lines = ["\(pad)\(path) array(\(items.count))"]
            for (idx, child) in items.enumerated() {
                lines.append(contentsOf: tree(from: child, path: "\(path)[\(idx)]", depth: depth + 1))
            }
            return lines
        case .string(let s):
            return ["\(pad)\(path) string \"\(s.prefix(40))\""]
        case .number(let n):
            return ["\(pad)\(path) number \(n)"]
        case .bool(let b):
            return ["\(pad)\(path) bool \(b)"]
        case .null:
            return ["\(pad)\(path) null"]
        }
    }

    private static func structuralOutline(_ text: String, language: String) -> String {
        let patterns: [(String, String)] = {
            switch language {
            case "swift":
                return [
                    (#"(?:(?:public|private|internal|fileprivate|open)\s+)?(?:final\s+)?(?:class|struct|enum|actor|protocol)\s+(\w+)"#, "type"),
                    (#"func\s+(\w+)"#, "func"),
                    (#"(?:let|var)\s+(\w+)"#, "binding"),
                ]
            case "python":
                return [
                    (#"class\s+(\w+)"#, "class"),
                    (#"def\s+(\w+)"#, "def"),
                ]
            case "js", "javascript", "ts", "typescript":
                return [
                    (#"class\s+(\w+)"#, "class"),
                    (#"function\s+(\w+)"#, "function"),
                    (#"(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s*)?\("#, "function"),
                    (#"(?:const|let|var)\s+(\w+)"#, "binding"),
                ]
            default:
                return [
                    (#"class\s+(\w+)"#, "class"),
                    (#"function\s+(\w+)"#, "function"),
                    (#"def\s+(\w+)"#, "def"),
                ]
            }
        }()

        var lines = ["language: \(language)", "root"]
        var depth = 1
        let sourceLines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        for (lineNumber, line) in sourceLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for (pattern, kind) in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if let match = regex.firstMatch(in: trimmed, range: range),
                   match.numberOfRanges > 1,
                   let nameRange = Range(match.range(at: 1), in: trimmed) {
                    lines.append(String(repeating: "  ", count: depth) + "\(kind) \(trimmed[nameRange])  (L\(lineNumber + 1))")
                }
            }
            let opens = trimmed.filter { "{[(".contains($0) }.count
            let closes = trimmed.filter { "}])".contains($0) }.count
            depth = max(1, depth + opens - closes)
        }

        let counts = [
            "",
            "braces: \(text.filter { $0 == "{" }.count)/\(text.filter { $0 == "}" }.count)",
            "parens: \(text.filter { $0 == "(" }.count)/\(text.filter { $0 == ")" }.count)",
            "brackets: \(text.filter { $0 == "[" }.count)/\(text.filter { $0 == "]" }.count)",
            "lines: \(sourceLines.count)",
            "chars: \(text.count)",
        ]
        return (lines + counts).joined(separator: "\n")
    }
}
