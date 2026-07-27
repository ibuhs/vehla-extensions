import Foundation

/// JSONPath evaluator supporting `$`, `.key`, `["key"]`, `[n]`, `[*]`,
/// `[start:end]`, `..` recursive descent, and simple `[?(@.key==value)]` filters.
enum JSONPathEngine {
    static func query(document: String, path: String) throws -> String {
        let root = try JSONValue.parse(document)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ToolError.invalidInput("JSONPath is required.") }
        let normalized = trimmed.hasPrefix("$") ? trimmed : "$\(trimmed.hasPrefix(".") || trimmed.hasPrefix("[") ? "" : ".")\(trimmed)"
        let results = try evaluate(root: root, path: normalized)
        if results.isEmpty { return "[]" }
        if results.count == 1 { return try results[0].encode(pretty: true) }
        return try JSONValue.array(results).encode(pretty: true)
    }

    private static func evaluate(root: JSONValue, path: String) throws -> [JSONValue] {
        var tokens = tokenize(path)
        guard tokens.first == .root else {
            throw ToolError.invalidInput("JSONPath must start with $.")
        }
        tokens.removeFirst()
        var current: [JSONValue] = [root]
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            index += 1
            switch token {
            case .root:
                continue
            case .dotName(let name):
                current = current.compactMap { child(of: $0, key: name) }
            case .wildcard:
                current = current.flatMap(children)
            case .index(let i):
                current = current.compactMap { child(of: $0, index: i) }
            case .slice(let start, let end):
                current = current.flatMap { slice($0, start: start, end: end) }
            case .recursive:
                current = current.flatMap(descendantsIncludingSelf)
            case .filter(let expression):
                current = try current.flatMap { try filterChildren($0, expression: expression) }
            case .bracketName(let name):
                current = current.compactMap { child(of: $0, key: name) }
            }
        }
        return current
    }

    private enum Token: Equatable {
        case root
        case dotName(String)
        case bracketName(String)
        case wildcard
        case index(Int)
        case slice(Int?, Int?)
        case recursive
        case filter(String)
    }

    private static func tokenize(_ path: String) -> [Token] {
        var tokens: [Token] = []
        var i = path.startIndex
        while i < path.endIndex {
            let ch = path[i]
            if ch == "$" {
                tokens.append(.root)
                i = path.index(after: i)
            } else if path[i...].hasPrefix("..") {
                tokens.append(.recursive)
                i = path.index(i, offsetBy: 2)
                if i < path.endIndex, path[i].isLetter || path[i] == "_" {
                    let start = i
                    while i < path.endIndex, path[i].isLetter || path[i].isNumber || path[i] == "_" {
                        i = path.index(after: i)
                    }
                    tokens.append(.dotName(String(path[start..<i])))
                }
            } else if ch == "." {
                i = path.index(after: i)
                if i < path.endIndex, path[i] == "*" {
                    tokens.append(.wildcard)
                    i = path.index(after: i)
                } else {
                    let start = i
                    while i < path.endIndex, path[i].isLetter || path[i].isNumber || path[i] == "_" {
                        i = path.index(after: i)
                    }
                    if start < i {
                        tokens.append(.dotName(String(path[start..<i])))
                    }
                }
            } else if ch == "[" {
                i = path.index(after: i)
                while i < path.endIndex, path[i].isWhitespace { i = path.index(after: i) }
                guard i < path.endIndex else { break }
                if path[i] == "'" || path[i] == "\"" {
                    let quote = path[i]
                    i = path.index(after: i)
                    let start = i
                    while i < path.endIndex, path[i] != quote { i = path.index(after: i) }
                    tokens.append(.bracketName(String(path[start..<i])))
                    if i < path.endIndex { i = path.index(after: i) }
                    while i < path.endIndex, path[i] != "]" { i = path.index(after: i) }
                    if i < path.endIndex { i = path.index(after: i) }
                } else if path[i] == "*" {
                    tokens.append(.wildcard)
                    i = path.index(after: i)
                    while i < path.endIndex, path[i] != "]" { i = path.index(after: i) }
                    if i < path.endIndex { i = path.index(after: i) }
                } else if path[i] == "?" {
                    i = path.index(after: i)
                    while i < path.endIndex, path[i].isWhitespace { i = path.index(after: i) }
                    if i < path.endIndex, path[i] == "(" { i = path.index(after: i) }
                    let start = i
                    var depth = 1
                    while i < path.endIndex, depth > 0 {
                        if path[i] == "(" { depth += 1 }
                        if path[i] == ")" { depth -= 1 }
                        if depth > 0 { i = path.index(after: i) }
                    }
                    let expr = String(path[start..<i]).trimmingCharacters(in: .whitespaces)
                    if i < path.endIndex, path[i] == ")" { i = path.index(after: i) }
                    while i < path.endIndex, path[i] != "]" { i = path.index(after: i) }
                    if i < path.endIndex { i = path.index(after: i) }
                    tokens.append(.filter(expr))
                } else {
                    let start = i
                    while i < path.endIndex, path[i] != "]" { i = path.index(after: i) }
                    let body = String(path[start..<i]).trimmingCharacters(in: .whitespaces)
                    if i < path.endIndex { i = path.index(after: i) }
                    if body.contains(":") {
                        let parts = body.split(separator: ":", maxSplits: 1).map {
                            $0.trimmingCharacters(in: .whitespaces)
                        }
                        let a = parts.first.flatMap { Int($0) }
                        let b = parts.count > 1 ? Int(parts[1]) : nil
                        tokens.append(.slice(a, b))
                    } else if let idx = Int(body) {
                        tokens.append(.index(idx))
                    }
                }
            } else {
                i = path.index(after: i)
            }
        }
        return tokens
    }

    private static func child(of value: JSONValue, key: String) -> JSONValue? {
        guard case .object(let pairs) = value else { return nil }
        return pairs.first(where: { $0.0 == key })?.1
    }

    private static func child(of value: JSONValue, index: Int) -> JSONValue? {
        guard case .array(let items) = value else { return nil }
        let idx = index >= 0 ? index : items.count + index
        guard items.indices.contains(idx) else { return nil }
        return items[idx]
    }

    private static func children(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let items): return items
        case .object(let pairs): return pairs.map(\.1)
        default: return []
        }
    }

    private static func slice(_ value: JSONValue, start: Int?, end: Int?) -> [JSONValue] {
        guard case .array(let items) = value else { return [] }
        let count = items.count
        var s = start ?? 0
        var e = end ?? count
        if s < 0 { s += count }
        if e < 0 { e += count }
        s = max(0, min(count, s))
        e = max(0, min(count, e))
        guard s < e else { return [] }
        return Array(items[s..<e])
    }

    private static func descendantsIncludingSelf(_ value: JSONValue) -> [JSONValue] {
        var result = [value]
        for child in children(value) {
            result.append(contentsOf: descendantsIncludingSelf(child))
        }
        return result
    }

    private static func filterChildren(_ value: JSONValue, expression: String) throws -> [JSONValue] {
        let candidates: [JSONValue]
        switch value {
        case .array(let items): candidates = items
        case .object: candidates = [value]
        default: return []
        }
        return try candidates.filter { try matchesFilter($0, expression: expression) }
    }

    private static func matchesFilter(_ value: JSONValue, expression: String) throws -> Bool {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        // @.key==value | @.key!=value | @.key | @.key>number
        let ops = ["==", "!=", ">=", "<=", ">", "<"]
        for op in ops {
            if let range = expr.range(of: op) {
                let left = String(expr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(expr[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                let lhs = try resolveFilterValue(value, path: left)
                let rhs = literal(right)
                switch op {
                case "==": return equal(lhs, rhs)
                case "!=": return !equal(lhs, rhs)
                case ">": return compare(lhs, rhs) == .orderedDescending
                case "<": return compare(lhs, rhs) == .orderedAscending
                case ">=": return compare(lhs, rhs) != .orderedAscending
                case "<=": return compare(lhs, rhs) != .orderedDescending
                default: break
                }
            }
        }
        let exists = try resolveFilterValue(value, path: expr)
        switch exists {
        case .null: return false
        case .bool(let b): return b
        default: return true
        }
    }

    private static func resolveFilterValue(_ root: JSONValue, path: String) throws -> JSONValue {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("@") { p.removeFirst() }
        if p.isEmpty { return root }
        let full = "$" + (p.hasPrefix(".") || p.hasPrefix("[") ? p : ".\(p)")
        let values = try evaluate(root: root, path: full)
        return values.first ?? .null
    }

    private static func literal(_ text: String) -> JSONValue {
        if text == "null" { return .null }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let number = Double(text) { return .number(number) }
        if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            return .string(String(text.dropFirst().dropLast()))
        }
        return .string(text)
    }

    private static func equal(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return true
        case (.bool(let x), .bool(let y)): return x == y
        case (.number(let x), .number(let y)): return x == y
        case (.string(let x), .string(let y)): return x == y
        default: return false
        }
    }

    private static func compare(_ a: JSONValue, _ b: JSONValue) -> ComparisonResult {
        guard case .number(let x) = a, case .number(let y) = b else { return .orderedSame }
        if x < y { return .orderedAscending }
        if x > y { return .orderedDescending }
        return .orderedSame
    }
}
