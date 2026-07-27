import Foundation

enum JSONValue: Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([(String, JSONValue)])

    static func parse(_ text: String) throws -> JSONValue {
        try ToolLimits.guardSize(text)
        guard let data = text.data(using: .utf8) else {
            throw ToolError.invalidInput("Input is not valid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try fromAny(object)
    }

    static func fromAny(_ value: Any) throws -> JSONValue {
        switch value {
        case is NSNull: return .null
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            return .number(n.doubleValue)
        case let s as String: return .string(s)
        case let a as [Any]:
            return .array(try a.map { try fromAny($0) })
        case let o as [String: Any]:
            let pairs = o.keys.sorted().map { key in (key, o[key]!) }
            return .object(try pairs.map { ($0.0, try fromAny($0.1)) })
        default:
            throw ToolError.failed("Unsupported JSON value type.")
        }
    }

    func toAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.toAny() }
        case .object(let o):
            var dict: [String: Any] = [:]
            for (k, v) in o { dict[k] = v.toAny() }
            return dict
        }
    }

    func encode(pretty: Bool) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: toAny(),
            options: pretty
                ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
                : [.sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]
        )
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.failed("Could not encode JSON as UTF-8.")
        }
        return ToolLimits.truncate(text)
    }
}

enum JSONHelpers {
    static func detectDuplicateKeys(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        var duplicates: [String] = []
        var stack: [Set<String>] = []
        var path: [String] = ["$"]
        var i = text.startIndex
        func skipWhitespace() {
            while i < text.endIndex, text[i].isWhitespace { i = text.index(after: i) }
        }
        func parseString() throws -> String {
            guard i < text.endIndex, text[i] == "\"" else {
                throw ToolError.invalidInput("Expected string.")
            }
            i = text.index(after: i)
            var out = ""
            while i < text.endIndex {
                let c = text[i]
                if c == "\\" {
                    let next = text.index(after: i)
                    guard next < text.endIndex else { throw ToolError.invalidInput("Bad escape.") }
                    out.append(text[next])
                    i = text.index(after: next)
                    continue
                }
                if c == "\"" {
                    i = text.index(after: i)
                    return out
                }
                out.append(c)
                i = text.index(after: i)
            }
            throw ToolError.invalidInput("Unterminated string.")
        }
        func parseValue() throws {
            skipWhitespace()
            guard i < text.endIndex else { throw ToolError.invalidInput("Unexpected end.") }
            switch text[i] {
            case "{":
                i = text.index(after: i)
                stack.append([])
                skipWhitespace()
                if i < text.endIndex, text[i] == "}" {
                    i = text.index(after: i)
                    _ = stack.popLast()
                    return
                }
                while true {
                    skipWhitespace()
                    let key = try parseString()
                    let full = (path + [key]).joined(separator: ".")
                    if var top = stack.last {
                        if top.contains(key) { duplicates.append(full) }
                        top.insert(key)
                        stack[stack.count - 1] = top
                    }
                    skipWhitespace()
                    guard i < text.endIndex, text[i] == ":" else {
                        throw ToolError.invalidInput("Expected ':' after key.")
                    }
                    i = text.index(after: i)
                    path.append(key)
                    try parseValue()
                    _ = path.popLast()
                    skipWhitespace()
                    guard i < text.endIndex else { throw ToolError.invalidInput("Unexpected end.") }
                    if text[i] == "," {
                        i = text.index(after: i)
                        continue
                    }
                    if text[i] == "}" {
                        i = text.index(after: i)
                        _ = stack.popLast()
                        break
                    }
                    throw ToolError.invalidInput("Expected ',' or '}'.")
                }
            case "[":
                i = text.index(after: i)
                skipWhitespace()
                if i < text.endIndex, text[i] == "]" {
                    i = text.index(after: i)
                    return
                }
                var index = 0
                while true {
                    path.append("[\(index)]")
                    try parseValue()
                    _ = path.popLast()
                    skipWhitespace()
                    guard i < text.endIndex else { throw ToolError.invalidInput("Unexpected end.") }
                    if text[i] == "," {
                        i = text.index(after: i)
                        index += 1
                        continue
                    }
                    if text[i] == "]" {
                        i = text.index(after: i)
                        break
                    }
                    throw ToolError.invalidInput("Expected ',' or ']'.")
                }
            case "\"":
                _ = try parseString()
            case "-", "0"..."9":
                while i < text.endIndex, "0123456789.+-eE".contains(text[i]) {
                    i = text.index(after: i)
                }
            case "t":
                guard text[i...].hasPrefix("true") else { throw ToolError.invalidInput("Invalid literal.") }
                i = text.index(i, offsetBy: 4)
            case "f":
                guard text[i...].hasPrefix("false") else { throw ToolError.invalidInput("Invalid literal.") }
                i = text.index(i, offsetBy: 5)
            case "n":
                guard text[i...].hasPrefix("null") else { throw ToolError.invalidInput("Invalid literal.") }
                i = text.index(i, offsetBy: 4)
            default:
                throw ToolError.invalidInput("Unexpected character \(text[i]).")
            }
        }
        try parseValue()
        if duplicates.isEmpty { return "No duplicate keys found." }
        return "Duplicate keys:\n" + duplicates.map { "• \($0)" }.joined(separator: "\n")
    }

    static func explore(_ value: JSONValue, path: String = "$") -> [String] {
        switch value {
        case .null: return ["\(path): null"]
        case .bool(let b): return ["\(path): bool (\(b))"]
        case .number(let n): return ["\(path): number (\(n))"]
        case .string(let s): return ["\(path): string (\(s.count) chars)"]
        case .array(let a):
            var lines = ["\(path): array (\(a.count) items)"]
            for (idx, item) in a.prefix(50).enumerated() {
                lines += explore(item, path: "\(path)[\(idx)]")
            }
            if a.count > 50 { lines.append("\(path): … \(a.count - 50) more items") }
            return lines
        case .object(let o):
            var lines = ["\(path): object (\(o.count) keys)"]
            for (key, item) in o.prefix(100) {
                lines += explore(item, path: "\(path).\(key)")
            }
            if o.count > 100 { lines.append("\(path): … \(o.count - 100) more keys") }
            return lines
        }
    }

    static func merge(_ base: JSONValue, _ overlay: JSONValue) -> JSONValue {
        guard case .object(let left) = base, case .object(let right) = overlay else {
            return overlay
        }
        var map = Dictionary(uniqueKeysWithValues: left)
        for (key, value) in right {
            if let existing = map[key] {
                map[key] = merge(existing, value)
            } else {
                map[key] = value
            }
        }
        return .object(map.keys.sorted().map { ($0, map[$0]!) })
    }

    static func inferSchema(_ value: JSONValue) -> [String: Any] {
        switch value {
        case .null: return ["type": "null"]
        case .bool: return ["type": "boolean"]
        case .number: return ["type": "number"]
        case .string: return ["type": "string"]
        case .array(let items):
            if let first = items.first {
                return ["type": "array", "items": inferSchema(first)]
            }
            return ["type": "array", "items": [:]]
        case .object(let pairs):
            var properties: [String: Any] = [:]
            var required: [String] = []
            for (key, child) in pairs {
                properties[key] = inferSchema(child)
                required.append(key)
            }
            return [
                "type": "object",
                "properties": properties,
                "required": required.sorted(),
            ]
        }
    }
}
