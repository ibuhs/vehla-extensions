import Foundation

enum JMESPathEngine {
    static func query(document: String, expression: String) throws -> String {
        let root = try JSONValue.parse(document)
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty || expr == "@" { return try root.encode(pretty: true) }
        let values = try evaluate(root, expression: expr)
        if values.count == 1 { return try values[0].encode(pretty: true) }
        return try JSONValue.array(values).encode(pretty: true)
    }

    private static func evaluate(_ root: JSONValue, expression: String) throws -> [JSONValue] {
        let stages = splitPipes(expression)
        var current: [JSONValue] = [root]
        for stage in stages {
            current = try applyStage(current, expression: stage)
        }
        return current
    }

    private static func splitPipes(_ expression: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote: Character?
        for ch in expression {
            if let q = inQuote {
                current.append(ch)
                if ch == q { inQuote = nil }
                continue
            }
            if ch == "'" || ch == "\"" {
                inQuote = ch
                current.append(ch)
                continue
            }
            if ch == "[" || ch == "(" || ch == "{" { depth += 1 }
            if ch == "]" || ch == ")" || ch == "}" { depth = max(0, depth - 1) }
            if ch == "|" && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    private static func applyStage(_ values: [JSONValue], expression: String) throws -> [JSONValue] {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        if expr == "*" {
            return values.flatMap(children)
        }
        if expr == "keys(@)" || expr == "keys" {
            return try values.map { value in
                guard case .object(let o) = value else {
                    throw ToolError.invalidInput("keys(@) requires an object.")
                }
                return .array(o.map { .string($0.0) })
            }
        }
        if expr == "length(@)" || expr == "length" {
            return values.map { value in
                switch value {
                case .array(let a): return .number(Double(a.count))
                case .object(let o): return .number(Double(o.count))
                case .string(let s): return .number(Double(s.count))
                default: return .number(1)
                }
            }
        }
        if expr.hasPrefix("[?") && expr.hasSuffix("]") {
            let filter = String(expr.dropFirst(2).dropLast())
            return try values.flatMap { value -> [JSONValue] in
                try filterCandidates(value).filter { try matchesFilter($0, filter) }
            }
        }
        if expr == "[]" || expr == "[*]" {
            return values.flatMap(children)
        }
        if expr.hasPrefix("[") && expr.hasSuffix("]") {
            let body = String(expr.dropFirst().dropLast())
            if let idx = Int(body) {
                return values.compactMap { child(of: $0, index: idx) }
            }
            if body.contains(":") {
                let parts = body.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                let start = parts.first.flatMap(Int.init)
                let end = parts.count > 1 ? Int(parts[1]) : nil
                return values.flatMap { slice($0, start: start, end: end) }
            }
        }
        if expr.hasPrefix("{") && expr.hasSuffix("}") {
            return try values.map { try multiSelect($0, expression: expr) }
        }

        // path with optional [*] projections: foo.bar[*].baz
        var current = values
        var token = ""
        var i = expr.startIndex
        func flushName() throws {
            let name = token.trimmingCharacters(in: .whitespaces)
            token = ""
            guard !name.isEmpty else { return }
            if name == "*" {
                current = current.flatMap(children)
            } else {
                current = current.compactMap { child(of: $0, key: name) }
            }
        }
        while i < expr.endIndex {
            let ch = expr[i]
            if ch == "." {
                try flushName()
                i = expr.index(after: i)
                continue
            }
            if ch == "[" {
                try flushName()
                guard let close = expr[i...].firstIndex(of: "]") else {
                    throw ToolError.invalidInput("Unclosed bracket in JMESPath.")
                }
                let body = String(expr[expr.index(after: i)..<close])
                if body == "*" || body.isEmpty {
                    current = current.flatMap(children)
                } else if body.hasPrefix("?") {
                    let filter = String(body.dropFirst())
                    current = try current.flatMap { value in
                        try filterCandidates(value).filter { try matchesFilter($0, filter) }
                    }
                } else if let idx = Int(body) {
                    current = current.compactMap { child(of: $0, index: idx) }
                } else if body.contains(":") {
                    let parts = body.split(separator: ":", maxSplits: 1).map {
                        $0.trimmingCharacters(in: .whitespaces)
                    }
                    current = current.flatMap {
                        slice($0, start: parts.first.flatMap(Int.init), end: parts.count > 1 ? Int(parts[1]) : nil)
                    }
                }
                i = expr.index(after: close)
                continue
            }
            token.append(ch)
            i = expr.index(after: i)
        }
        try flushName()
        return current
    }

    private static func multiSelect(_ value: JSONValue, expression: String) throws -> JSONValue {
        let body = String(expression.dropFirst().dropLast())
        var pairs: [(String, JSONValue)] = []
        for part in body.split(separator: ",") {
            let bits = part.split(separator: ":", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard bits.count == 2 else { continue }
            let key = bits[0]
            let selected = try evaluate(value, expression: bits[1])
            pairs.append((key, selected.first ?? .null))
        }
        return .object(pairs)
    }

    private static func matchesFilter(_ value: JSONValue, _ expression: String) throws -> Bool {
        let expr = expression.trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        let ops = ["==", "!=", ">=", "<=", ">", "<"]
        for op in ops where expr.contains(op) {
            let parts = expr.components(separatedBy: op)
            guard parts.count == 2 else { continue }
            let left = try resolve(value, parts[0].trimmingCharacters(in: .whitespaces))
            let right = literal(parts[1].trimmingCharacters(in: .whitespaces))
            switch op {
            case "==": return equal(left, right)
            case "!=": return !equal(left, right)
            case ">": return compare(left, right) == .orderedDescending
            case "<": return compare(left, right) == .orderedAscending
            case ">=": return compare(left, right) != .orderedAscending
            case "<=": return compare(left, right) != .orderedDescending
            default: break
            }
        }
        let exists = try resolve(value, expr)
        if case .null = exists { return false }
        if case .bool(let b) = exists { return b }
        return true
    }

    private static func resolve(_ root: JSONValue, _ path: String) throws -> JSONValue {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("@.") { p = String(p.dropFirst(2)) }
        else if p == "@" { return root }
        else if p.hasPrefix("@") { p = String(p.dropFirst()) }
        let values = try evaluate(root, expression: p)
        return values.first ?? .null
    }

    private static func children(_ value: JSONValue) -> [JSONValue] {
        switch value {
        case .array(let a): return a
        case .object(let o): return o.map(\.1)
        default: return []
        }
    }

    private static func filterCandidates(_ value: JSONValue) -> [JSONValue] {
        // Projection filters apply to array elements; objects fall back to values.
        if case .array(let a) = value { return a }
        return children(value)
    }

    private static func child(of value: JSONValue, key: String) -> JSONValue? {
        guard case .object(let o) = value else { return nil }
        return o.first(where: { $0.0 == key })?.1
    }

    private static func child(of value: JSONValue, index: Int) -> JSONValue? {
        guard case .array(let a) = value else { return nil }
        let idx = index >= 0 ? index : a.count + index
        guard a.indices.contains(idx) else { return nil }
        return a[idx]
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

    private static func literal(_ text: String) -> JSONValue {
        var value = text.trimmingCharacters(in: .whitespaces)
        if (value.hasPrefix("`") && value.hasSuffix("`"))
            || (value.hasPrefix("'") && value.hasSuffix("'"))
            || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            value = String(value.dropFirst().dropLast())
            if let n = Double(value) { return .number(n) }
            if value == "true" { return .bool(true) }
            if value == "false" { return .bool(false) }
            if value == "null" { return .null }
            return .string(value)
        }
        if value == "null" { return .null }
        if value == "true" { return .bool(true) }
        if value == "false" { return .bool(false) }
        if let n = Double(value) { return .number(n) }
        return .string(value)
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

enum JQEngine {
    static func query(document: String, filter: String) throws -> String {
        let root = try JSONValue.parse(document)
        let trimmed = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return try root.encode(pretty: true) }
        let values = try evaluate([root], filter: trimmed)
        if values.count == 1 { return try values[0].encode(pretty: true) }
        return try JSONValue.array(values).encode(pretty: true)
    }

    private static func evaluate(_ inputs: [JSONValue], filter: String) throws -> [JSONValue] {
        let stages = splitPipes(filter)
        var current = inputs
        for stage in stages {
            current = try apply(current, filter: stage)
        }
        return current
    }

    private static func splitPipes(_ filter: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        var inQuote: Character?
        for ch in filter {
            if let q = inQuote {
                current.append(ch)
                if ch == q { inQuote = nil }
                continue
            }
            if ch == "'" || ch == "\"" {
                inQuote = ch
                current.append(ch)
                continue
            }
            if "[{(".contains(ch) { depth += 1 }
            if "]})".contains(ch) { depth = max(0, depth - 1) }
            if ch == "|" && depth == 0 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }

    private static func apply(_ inputs: [JSONValue], filter: String) throws -> [JSONValue] {
        let expr = filter.trimmingCharacters(in: .whitespaces)
        switch expr {
        case ".", "identity":
            return inputs
        case "keys":
            return try inputs.map {
                guard case .object(let o) = $0 else { throw ToolError.invalidInput("keys requires an object.") }
                return .array(o.map { .string($0.0) })
            }
        case "keys_unsorted":
            return try apply(inputs, filter: "keys")
        case "length":
            return inputs.map(lengthValue)
        case "type":
            return inputs.map { .string(typeName($0)) }
        case "values":
            return inputs.flatMap { value -> [JSONValue] in
                switch value {
                case .object(let o): return o.map(\.1)
                case .array(let a): return a
                default: return []
                }
            }
        case "to_entries":
            return try inputs.map {
                guard case .object(let o) = $0 else { throw ToolError.invalidInput("to_entries requires an object.") }
                return .array(o.map { .object([("key", .string($0.0)), ("value", $0.1)]) })
            }
        case "from_entries":
            return try inputs.map {
                guard case .array(let a) = $0 else { throw ToolError.invalidInput("from_entries requires an array.") }
                var pairs: [(String, JSONValue)] = []
                for item in a {
                    guard case .object(let o) = item,
                          let key = o.first(where: { $0.0 == "key" })?.1,
                          case .string(let name) = key,
                          let value = o.first(where: { $0.0 == "value" })?.1
                    else { continue }
                    pairs.append((name, value))
                }
                return .object(pairs)
            }
        case "first":
            return inputs.compactMap {
                if case .array(let a) = $0 { return a.first }
                return $0
            }
        case "last":
            return inputs.compactMap {
                if case .array(let a) = $0 { return a.last }
                return $0
            }
        case "reverse":
            return inputs.map {
                if case .array(let a) = $0 { return .array(a.reversed()) }
                return $0
            }
        case "sort":
            return try inputs.map {
                guard case .array(let a) = $0 else { throw ToolError.invalidInput("sort requires an array.") }
                return .array(a.sorted(by: jqLessThan))
            }
        case "unique":
            return try inputs.map {
                guard case .array(let a) = $0 else { throw ToolError.invalidInput("unique requires an array.") }
                var seen: [String] = []
                var out: [JSONValue] = []
                for item in a {
                    let key = try item.encode(pretty: false)
                    if seen.contains(key) { continue }
                    seen.append(key)
                    out.append(item)
                }
                return .array(out)
            }
        case "flatten":
            return inputs.map {
                guard case .array(let a) = $0 else { return $0 }
                var out: [JSONValue] = []
                for item in a {
                    if case .array(let nested) = item { out.append(contentsOf: nested) }
                    else { out.append(item) }
                }
                return .array(out)
            }
        default:
            break
        }

        if expr.hasPrefix("map(") && expr.hasSuffix(")") {
            let inner = String(expr.dropFirst(4).dropLast())
            return try inputs.map { value in
                guard case .array(let a) = value else {
                    throw ToolError.invalidInput("map requires an array.")
                }
                let mapped = try evaluate(a, filter: inner)
                return .array(mapped)
            }
        }
        if expr.hasPrefix("select(") && expr.hasSuffix(")") {
            let inner = String(expr.dropFirst(7).dropLast())
            return try inputs.filter { try selectMatches($0, expression: inner) }
        }
        if expr.hasPrefix("has(") && expr.hasSuffix(")") {
            let key = String(expr.dropFirst(4).dropLast())
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return inputs.map { value in
                guard case .object(let o) = value else { return .bool(false) }
                return .bool(o.contains(where: { $0.0 == key }))
            }
        }
        if expr == ".[]" || expr == "[]" {
            return inputs.flatMap(arrayChildren)
        }
        if expr.hasPrefix(".") {
            // Support .foo.bar[0].baz and .[0]
            return try path(inputs, expr)
        }
        throw ToolError.invalidInput(
            "Unsupported jq filter. Try ., .path, .[], .[0], keys, length, type, map(...), select(...), pipes (|)."
        )
    }

    private static func path(_ inputs: [JSONValue], _ expr: String) throws -> [JSONValue] {
        // Convert jq path to JSONPath-ish evaluation per input.
        var current = inputs
        var i = expr.index(after: expr.startIndex) // skip leading .
        var name = ""
        func flush() {
            let key = name
            name = ""
            guard !key.isEmpty else { return }
            current = current.compactMap { child(of: $0, key: key) }
        }
        while i < expr.endIndex {
            let ch = expr[i]
            if ch == "." {
                flush()
                i = expr.index(after: i)
                continue
            }
            if ch == "[" {
                flush()
                guard let close = expr[i...].firstIndex(of: "]") else {
                    throw ToolError.invalidInput("Unclosed [] in jq path.")
                }
                let body = String(expr[expr.index(after: i)..<close])
                if body.isEmpty {
                    current = current.flatMap(arrayChildren)
                } else if let idx = Int(body) {
                    current = current.compactMap { child(of: $0, index: idx) }
                } else if (body.hasPrefix("\"") && body.hasSuffix("\"")) || (body.hasPrefix("'") && body.hasSuffix("'")) {
                    let key = String(body.dropFirst().dropLast())
                    current = current.compactMap { child(of: $0, key: key) }
                }
                i = expr.index(after: close)
                continue
            }
            name.append(ch)
            i = expr.index(after: i)
        }
        flush()
        return current
    }

    private static func selectMatches(_ value: JSONValue, expression: String) throws -> Bool {
        let expr = expression.trimmingCharacters(in: .whitespaces)
        let ops = ["==", "!=", ">=", "<=", ">", "<"]
        for op in ops where expr.contains(op) {
            let parts = expr.components(separatedBy: op)
            guard parts.count == 2 else { continue }
            let left = try evaluate([value], filter: parts[0].trimmingCharacters(in: .whitespaces)).first ?? .null
            let rightLiteral = parts[1].trimmingCharacters(in: .whitespaces)
            let right: JSONValue
            if rightLiteral.hasPrefix(".") {
                right = try evaluate([value], filter: rightLiteral).first ?? .null
            } else {
                right = literal(rightLiteral)
            }
            switch op {
            case "==": return equal(left, right)
            case "!=": return !equal(left, right)
            case ">": return compare(left, right) == .orderedDescending
            case "<": return compare(left, right) == .orderedAscending
            case ">=": return compare(left, right) != .orderedAscending
            case "<=": return compare(left, right) != .orderedDescending
            default: break
            }
        }
        if expr.hasPrefix(".") || expr == "true" || expr == "false" {
            let result = try evaluate([value], filter: expr).first ?? .null
            if case .bool(let b) = result { return b }
            if case .null = result { return false }
            return true
        }
        return true
    }

    private static func arrayChildren(_ value: JSONValue) -> [JSONValue] {
        if case .array(let a) = value { return a }
        return []
    }

    private static func child(of value: JSONValue, key: String) -> JSONValue? {
        guard case .object(let o) = value else { return nil }
        return o.first(where: { $0.0 == key })?.1
    }

    private static func child(of value: JSONValue, index: Int) -> JSONValue? {
        guard case .array(let a) = value else { return nil }
        let idx = index >= 0 ? index : a.count + index
        guard a.indices.contains(idx) else { return nil }
        return a[idx]
    }

    private static func lengthValue(_ value: JSONValue) -> JSONValue {
        switch value {
        case .array(let a): return .number(Double(a.count))
        case .object(let o): return .number(Double(o.count))
        case .string(let s): return .number(Double(s.count))
        case .null: return .number(0)
        default: return .number(1)
        }
    }

    private static func typeName(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool: return "boolean"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

    private static func literal(_ text: String) -> JSONValue {
        if text == "null" { return .null }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let n = Double(text) { return .number(n) }
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

    private static func jqLessThan(_ a: JSONValue, _ b: JSONValue) -> Bool {
        switch (a, b) {
        case (.number(let x), .number(let y)): return x < y
        case (.string(let x), .string(let y)): return x < y
        default: return false
        }
    }
}
