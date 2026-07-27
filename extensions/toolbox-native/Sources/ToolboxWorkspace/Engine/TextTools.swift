import Foundation

actor TextTools {
    func run(_ request: ToolRequest) throws -> ToolOutput {
        try ToolLimits.guardSize(request.primary)
        if !request.secondary.isEmpty { try ToolLimits.guardSize(request.secondary, label: "Secondary input") }
        switch request.toolID {
        case "text.regex":
            return try ToolOutput(regexTest(request))
        case "text.regexGen":
            return ToolOutput(NSRegularExpression.escapedPattern(for: request.primary))
        case "text.regexExplain":
            return ToolOutput(explainRegex(request.primary))
        case "text.diff":
            return ToolOutput(TextDiff.lineDiff(request.primary, request.secondary))
        case "text.merge":
            return ToolOutput(merge(request))
        case "text.mdPreview":
            return markdownEditorOutput(request.primary, normalize: false)
        case "text.mdEditor":
            return markdownEditorOutput(request.primary, normalize: true)
        case "text.htmlPreview":
            return ToolOutput(stripHTML(request.primary))
        case "text.compare":
            return ToolOutput(compare(request.primary, request.secondary))
        case "text.charCount":
            return ToolOutput(charCount(request.primary))
        case "text.wordCount":
            return ToolOutput(wordCount(request.primary))
        case "text.lineCount":
            return ToolOutput(lineCount(request.primary))
        case "text.dedupe":
            return ToolOutput(dedupe(request.primary))
        case "text.sort":
            return ToolOutput(sortLines(request))
        case "text.reverse":
            return ToolOutput(request.primary.split(whereSeparator: \.isNewline).reversed().joined(separator: "\n"))
        case "text.trim":
            return ToolOutput(trim(request.primary))
        case "text.case":
            return ToolOutput(caseConvert(request))
        case "text.slug":
            return ToolOutput(slug(request.primary))
        case "text.lorem":
            return ToolOutput(lorem(request))
        case "text.uuidReplace":
            return ToolOutput(uuidReplace(request.primary))
        case "text.findReplace":
            return ToolOutput(findReplace(request))
        case "text.wrap":
            return ToolOutput(wrap(request))
        case "text.random":
            return ToolOutput(randomText(request))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func regexTest(_ request: ToolRequest) throws -> String {
        let pattern = request.secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { throw ToolError.invalidInput("Pattern is required.") }
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(request.primary.startIndex..<request.primary.endIndex, in: request.primary)
        let matches = regex.matches(in: request.primary, range: range)
        if matches.isEmpty { return "No matches." }
        var lines = ["\(matches.count) match(es)"]
        for (index, match) in matches.prefix(200).enumerated() {
            guard let full = Range(match.range, in: request.primary) else { continue }
            lines.append("[\(index)] \(request.primary[full])")
            for g in 1..<match.numberOfRanges {
                if let gr = Range(match.range(at: g), in: request.primary) {
                    lines.append("  group \(g): \(request.primary[gr])")
                }
            }
        }
        return ToolLimits.truncate(lines.joined(separator: "\n"))
    }

    private func explainRegex(_ pattern: String) -> String {
        var lines = ["Pattern: \(pattern)", ""]
        if (try? NSRegularExpression(pattern: pattern)) != nil {
            lines.append("Valid NSRegularExpression / ICU pattern.")
        } else {
            lines.append("Warning: pattern failed to compile as NSRegularExpression.")
        }
        lines.append("")
        lines.append("Token walk:")
        var i = pattern.startIndex
        var group = 0
        while i < pattern.endIndex {
            let ch = pattern[i]
            if ch == "\\" {
                let next = pattern.index(after: i)
                if next < pattern.endIndex {
                    let esc = pattern[next]
                    lines.append(explainEscape(esc))
                    i = pattern.index(after: next)
                    continue
                }
            }
            switch ch {
            case "^": lines.append("• ^ — start of string/line anchor")
            case "$": lines.append("• $ — end of string/line anchor")
            case ".": lines.append("• . — any character (except newline unless s-flag)")
            case "*": lines.append("• * — quantify previous atom 0+ times")
            case "+": lines.append("• + — quantify previous atom 1+ times")
            case "?": lines.append("• ? — quantify previous atom 0 or 1 time / make quantifier lazy")
            case "|": lines.append("• | — alternation (OR)")
            case "(":
                group += 1
                let rest = pattern[i...]
                if rest.hasPrefix("(?:") {
                    lines.append("• (?:…) — non-capturing group")
                } else if rest.hasPrefix("(?=") {
                    lines.append("• (?=…) — positive lookahead")
                } else if rest.hasPrefix("(?!") {
                    lines.append("• (?!…) — negative lookahead")
                } else if rest.hasPrefix("(?<=") {
                    lines.append("• (?<=…) — positive lookbehind")
                } else if rest.hasPrefix("(?<!") {
                    lines.append("• (?<!…) — negative lookbehind")
                } else {
                    lines.append("• ( — capture group #\(group)")
                }
            case ")": lines.append("• ) — end group")
            case "[":
                if let close = pattern[i...].dropFirst().firstIndex(of: "]") {
                    let body = pattern[pattern.index(after: i)..<close]
                    lines.append("• [\(body)] — character class")
                    i = pattern.index(after: close)
                    continue
                }
                lines.append("• [ — character class (unclosed)")
            case "{":
                if let close = pattern[i...].firstIndex(of: "}") {
                    let body = pattern[i...close]
                    lines.append("• \(body) — explicit quantifier")
                    i = pattern.index(after: close)
                    continue
                }
                lines.append("• { — quantifier (unclosed)")
            case "]", "}":
                break
            default:
                if ch.isNewline {
                    lines.append("• newline literal")
                } else if ch.isWhitespace {
                    lines.append("• whitespace literal")
                } else {
                    lines.append("• literal \(ch)")
                }
            }
            i = pattern.index(after: i)
        }
        return lines.joined(separator: "\n")
    }

    private func explainEscape(_ esc: Character) -> String {
        switch esc {
        case "d": return "• \\d — digit [0-9]"
        case "D": return "• \\D — non-digit"
        case "w": return "• \\w — word character [A-Za-z0-9_]"
        case "W": return "• \\W — non-word character"
        case "s": return "• \\s — whitespace"
        case "S": return "• \\S — non-whitespace"
        case "b": return "• \\b — word boundary"
        case "B": return "• \\B — non-word boundary"
        case "n": return "• \\n — newline"
        case "t": return "• \\t — tab"
        case "r": return "• \\r — carriage return"
        default: return "• \\\(esc) — escaped literal"
        }
    }

    private func markdownEditorOutput(_ text: String, normalize: Bool) -> ToolOutput {
        let source = normalize ? normalizeMarkdown(text) : text
        let plain = markdownPreview(source)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"/>
        <style>
          body { font: 15px/1.55 ui-sans-serif, system-ui, sans-serif; margin: 1.25rem; color: #0f172a; background: #f8fafc; }
          pre, code { font-family: ui-monospace, Menlo, monospace; }
          pre { background: #e2e8f0; padding: 0.75rem; border-radius: 8px; overflow: auto; }
          code { background: #e2e8f0; padding: 0.1rem 0.3rem; border-radius: 4px; }
          a { color: #2563eb; }
          h1,h2,h3 { line-height: 1.25; }
        </style></head><body>
        \(markdownToHTML(source))
        </body></html>
        """
        return ToolOutput(plain, meta: normalize ? "markdown editor" : "markdown preview", previewHTML: html)
    }

    private func markdownToHTML(_ text: String) -> String {
        var html = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        html = html.replacingOccurrences(
            of: #"```([\s\S]*?)```"#,
            with: "<pre><code>$1</code></pre>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^### (.+)$"#,
            with: "<h3>$1</h3>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^## (.+)$"#,
            with: "<h2>$1</h2>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^# (.+)$"#,
            with: "<h1>$1</h1>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"\*([^*]+)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(
            of: #"(?m)^- (.+)$"#,
            with: "<li>$1</li>",
            options: .regularExpression
        )
        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        return "<p>\(html)</p>"
    }

    private func merge(_ request: ToolRequest) -> String {
        let parts = request.primary.components(separatedBy: "\n---\n")
        let base = parts.first ?? ""
        let ours = parts.count > 1 ? parts[1] : base
        let theirs = request.secondary
        let baseLines = base.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let ourLines = ours.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let theirLines = theirs.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var result: [String] = []
        let maxCount = max(baseLines.count, ourLines.count, theirLines.count)
        for i in 0..<maxCount {
            let b = i < baseLines.count ? baseLines[i] : nil
            let o = i < ourLines.count ? ourLines[i] : nil
            let t = i < theirLines.count ? theirLines[i] : nil
            if o == t {
                result.append(o ?? t ?? "")
            } else if o == b {
                result.append(t ?? o ?? "")
            } else if t == b {
                result.append(o ?? t ?? "")
            } else {
                result.append("<<<<<<< ours")
                result.append(o ?? "")
                result.append("=======")
                result.append(t ?? "")
                result.append(">>>>>>> theirs")
            }
        }
        return result.joined(separator: "\n")
    }

    private func markdownPreview(_ text: String) -> String {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .full)
        ) {
            return String(attributed.characters)
        }
        return text
    }

    private func normalizeMarkdown(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    private func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private func compare(_ left: String, _ right: String) -> String {
        let equal = left == right
        let leftCount = left.count
        let rightCount = right.count
        let shared = zip(left, right).prefix(while: { $0 == $1 }).count
        let similarity = Double(shared * 2) / Double(max(leftCount + rightCount, 1))
        return [
            "equal: \(equal)",
            "leftChars: \(leftCount)",
            "rightChars: \(rightCount)",
            String(format: "prefixSimilarity: %.1f%%", similarity * 100),
        ].joined(separator: "\n")
    }

    private func charCount(_ text: String) -> String {
        [
            "characters: \(text.count)",
            "utf8Bytes: \(text.utf8.count)",
            "unicodeScalars: \(text.unicodeScalars.count)",
            "withoutWhitespace: \(text.filter { !$0.isWhitespace }.count)",
        ].joined(separator: "\n")
    }

    private func wordCount(_ text: String) -> String {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return "words: \(words.count)"
    }

    private func lineCount(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return "lines: \(lines.count)\nnonEmpty: \(nonEmpty.count)"
    }

    private func dedupe(_ text: String) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init) {
            if seen.insert(line).inserted { result.append(line) }
        }
        return result.joined(separator: "\n")
    }

    private func sortLines(_ request: ToolRequest) -> String {
        let order = (request.options["order"] ?? "asc").lowercased()
        var lines = request.primary.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        lines.sort()
        if order.contains("desc") { lines.reverse() }
        return lines.joined(separator: "\n")
    }

    private func trim(_ text: String) -> String {
        text
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func caseConvert(_ request: ToolRequest) -> String {
        let mode = (request.options["mode"] ?? "upper").lowercased()
        let text = request.primary
        switch mode {
        case "lower": return text.lowercased()
        case "title":
            return text.lowercased().split(separator: " ").map {
                $0.prefix(1).uppercased() + $0.dropFirst()
            }.joined(separator: " ")
        case "camel":
            let parts = slug(text).split(separator: "-")
            guard let first = parts.first else { return "" }
            return first.lowercased() + parts.dropFirst().map {
                $0.prefix(1).uppercased() + $0.dropFirst()
            }.joined()
        case "snake":
            return slug(text).replacingOccurrences(of: "-", with: "_")
        case "kebab":
            return slug(text)
        default:
            return text.uppercased()
        }
    }

    private func slug(_ text: String) -> String {
        let folded = text.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        let mapped = folded.map { character -> Character in
            if character.isLetter || character.isNumber { return character }
            return "-"
        }
        return String(mapped)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func lorem(_ request: ToolRequest) -> String {
        let count = min(20, max(1, Int(request.options["paragraphs"] ?? "2") ?? 2))
        let paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat."
        return (0..<count).map { _ in paragraph }.joined(separator: "\n\n")
    }

    private func uuidReplace(_ text: String) -> String {
        let pattern = #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var result = text
        let matches = regex.matches(in: text, range: range).reversed()
        for match in matches {
            guard let r = Range(match.range, in: result) else { continue }
            result.replaceSubrange(r, with: UUID().uuidString.lowercased())
        }
        return result
    }

    private func findReplace(_ request: ToolRequest) -> String {
        let find = request.options["find"] ?? ""
        let replace = request.options["replace"] ?? ""
        guard !find.isEmpty else { return request.primary }
        return request.primary.replacingOccurrences(of: find, with: replace)
    }

    private func wrap(_ request: ToolRequest) -> String {
        let width = min(200, max(10, Int(request.options["width"] ?? "80") ?? 80))
        var lines: [String] = []
        for paragraph in request.primary.components(separatedBy: "\n") {
            if paragraph.isEmpty {
                lines.append("")
                continue
            }
            var current = ""
            for word in paragraph.split(separator: " ") {
                if current.isEmpty {
                    current = String(word)
                } else if current.count + 1 + word.count <= width {
                    current += " " + word
                } else {
                    lines.append(current)
                    current = String(word)
                }
            }
            if !current.isEmpty { lines.append(current) }
        }
        return lines.joined(separator: "\n")
    }

    private func randomText(_ request: ToolRequest) -> String {
        let count = min(500, max(1, Int(request.options["words"] ?? "50") ?? 50))
        let lexicon = [
            "alpha", "bravo", "cache", "delta", "echo", "flux", "gamma", "harbor",
            "index", "jade", "kite", "lunar", "matrix", "nova", "orbit", "pulse",
            "quartz", "ridge", "signal", "timber", "ultra", "vector", "wave", "xenon",
            "yield", "zenith",
        ]
        return (0..<count).map { _ in lexicon.randomElement()! }.joined(separator: " ")
    }
}

enum TextDiff {
    static func lineDiff(_ left: String, _ right: String) -> String {
        let a = left.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let b = right.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let table = lcsTable(a, b)
        var lines: [String] = []
        var i = a.count
        var j = b.count
        var ops: [(String, String)] = []
        while i > 0 || j > 0 {
            if i > 0, j > 0, a[i - 1] == b[j - 1] {
                ops.append((" ", a[i - 1]))
                i -= 1
                j -= 1
            } else if j > 0, (i == 0 || table[i][j - 1] >= table[i - 1][j]) {
                ops.append(("+", b[j - 1]))
                j -= 1
            } else if i > 0 {
                ops.append(("-", a[i - 1]))
                i -= 1
            }
        }
        for (mark, line) in ops.reversed() {
            lines.append("\(mark) \(line)")
        }
        return ToolLimits.truncate(lines.joined(separator: "\n"))
    }

    private static func lcsTable(_ a: [String], _ b: [String]) -> [[Int]] {
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    table[i][j] = table[i - 1][j - 1] + 1
                } else {
                    table[i][j] = max(table[i - 1][j], table[i][j - 1])
                }
            }
        }
        return table
    }
}
