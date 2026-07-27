import BSON
import Foundation
import TOMLKit
import Yams

actor JSONTools {
    func run(_ request: ToolRequest) throws -> ToolOutput {
        switch request.toolID {
        case "json.formatter":
            return try ToolOutput(JSONValue.parse(request.primary).encode(pretty: true))
        case "json.minifier":
            return try ToolOutput(JSONValue.parse(request.primary).encode(pretty: false))
        case "json.validator":
            _ = try JSONValue.parse(request.primary)
            return ToolOutput("Valid JSON.", meta: "\(request.primary.utf8.count) bytes")
        case "json.diff":
            let left = try JSONValue.parse(request.primary).encode(pretty: true)
            let right = try JSONValue.parse(request.secondary).encode(pretty: true)
            return ToolOutput(TextDiff.lineDiff(left, right))
        case "json.merge":
            let merged = JSONHelpers.merge(
                try JSONValue.parse(request.primary),
                try JSONValue.parse(request.secondary)
            )
            return try ToolOutput(merged.encode(pretty: true))
        case "json.toCsv":
            return try ToolOutput(jsonToCSV(request.primary))
        case "json.fromCsv":
            return try ToolOutput(csvToJSON(request.primary))
        case "json.xml":
            let direction = (request.options["direction"] ?? "xml-to-json").lowercased()
            if direction.contains("json") && direction.contains("to") && direction.hasPrefix("json") {
                return try ToolOutput(jsonToXML(request.primary))
            }
            if direction == "json-to-xml" {
                return try ToolOutput(jsonToXML(request.primary))
            }
            return try ToolOutput(xmlToJSON(request.primary))
        case "json.yaml":
            let direction = (request.options["direction"] ?? "yaml-to-json").lowercased()
            if direction == "json-to-yaml" {
                return try ToolOutput(jsonToYAML(request.primary))
            }
            return try ToolOutput(yamlToJSON(request.primary))
        case "json.toml":
            let direction = (request.options["direction"] ?? "toml-to-json").lowercased()
            if direction == "json-to-toml" {
                return try ToolOutput(jsonToTOML(request.primary))
            }
            return try ToolOutput(tomlToJSON(request.primary))
        case "json.ini":
            return try ToolOutput(iniToJSON(request.primary))
        case "json.bson":
            return try ToolOutput(decodeBSON(request.primary))
        case "json.msgpack":
            return try ToolOutput(decodeMessagePack(request.primary))
        case "json.ndjson":
            return try ToolOutput(prettyNDJSON(request.primary))
        case "json.prettyNested":
            return try ToolOutput(JSONValue.parse(request.primary).encode(pretty: true))
        case "json.duplicateKeys":
            return try ToolOutput(JSONHelpers.detectDuplicateKeys(request.primary))
        case "json.explorer":
            let value = try JSONValue.parse(request.primary)
            let lines = JSONHelpers.explore(value)
            return ToolOutput(ToolLimits.truncate(lines.joined(separator: "\n")), meta: "\(lines.count) nodes")
        case "json.jsonpath":
            return try ToolOutput(JSONPathEngine.query(document: request.primary, path: request.secondary))
        case "json.jmespath":
            return try ToolOutput(JMESPathEngine.query(document: request.primary, expression: request.secondary))
        case "json.jq":
            return try ToolOutput(JQEngine.query(document: request.primary, filter: request.secondary))
        case "json.schema":
            let schema = JSONHelpers.inferSchema(try JSONValue.parse(request.primary))
            let data = try JSONSerialization.data(withJSONObject: schema, options: [.prettyPrinted, .sortedKeys])
            return ToolOutput(String(data: data, encoding: .utf8) ?? "{}")
        case "json.fake":
            let count = Int(request.options["count"] ?? "1") ?? 1
            return try ToolOutput(fakeJSON(from: request.primary, count: min(max(count, 1), 100)))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func jsonToCSV(_ text: String) throws -> String {
        let value = try JSONValue.parse(text)
        guard case .array(let rows) = value else {
            throw ToolError.invalidInput("Expected a JSON array of objects.")
        }
        var keys: [String] = []
        var seen = Set<String>()
        for row in rows {
            guard case .object(let pairs) = row else { continue }
            for (key, _) in pairs where !seen.contains(key) {
                seen.insert(key)
                keys.append(key)
            }
        }
        var lines = [keys.map(csvEscape).joined(separator: ",")]
        for row in rows {
            guard case .object(let pairs) = row else { continue }
            let map = Dictionary(uniqueKeysWithValues: pairs.map { ($0.0, $0.1) })
            let cells = keys.map { key -> String in
                guard let cell = map[key] else { return "" }
                switch cell {
                case .null: return ""
                case .string(let s): return csvEscape(s)
                default: return csvEscape((try? cell.encode(pretty: false)) ?? "")
                }
            }
            lines.append(cells.joined(separator: ","))
        }
        return ToolLimits.truncate(lines.joined(separator: "\n"))
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func csvToJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        let rows = parseCSV(text)
        guard let header = rows.first, header.count > 0 else {
            throw ToolError.invalidInput("CSV is empty.")
        }
        let objects: [[String: String]] = rows.dropFirst().map { row in
            var dict: [String: String] = [:]
            for (index, key) in header.enumerated() {
                dict[key] = index < row.count ? row[index] : ""
            }
            return dict
        }
        let data = try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        i = text.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else if c == "\r" {
                // skip
            } else {
                field.append(c)
            }
            i = text.index(after: i)
        }
        row.append(field)
        if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
        return rows
    }

    private func xmlToJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        let parser = SimpleXMLParser()
        let value = try parser.parse(text)
        return try value.encode(pretty: true)
    }

    private func jsonToXML(_ text: String) throws -> String {
        let value = try JSONValue.parse(text)
        return ToolLimits.truncate(xmlString(value, name: "root", indent: 0))
    }

    private func xmlString(_ value: JSONValue, name: String, indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case .null: return "\(pad)<\(name)/>"
        case .bool(let b): return "\(pad)<\(name)>\(b)</\(name)>"
        case .number(let n): return "\(pad)<\(name)>\(n)</\(name)>"
        case .string(let s):
            let escaped = s
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return "\(pad)<\(name)>\(escaped)</\(name)>"
        case .array(let items):
            return items.map { xmlString($0, name: name, indent: indent) }.joined(separator: "\n")
        case .object(let pairs):
            let children = pairs.map { xmlString($0.1, name: sanitizeXMLName($0.0), indent: indent + 1) }
                .joined(separator: "\n")
            return "\(pad)<\(name)>\n\(children)\n\(pad)</\(name)>"
        }
    }

    private func sanitizeXMLName(_ name: String) -> String {
        let cleaned = name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" }
        let value = String(cleaned)
        if value.first?.isNumber == true { return "n_\(value)" }
        return value.isEmpty ? "item" : value
    }

    private func yamlToJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        guard let loaded = try Yams.load(yaml: text) else {
            return "null"
        }
        let data = try JSONSerialization.data(
            withJSONObject: sanitizeJSONObject(loaded),
            options: [.prettyPrinted, .sortedKeys]
        )
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func jsonToYAML(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        return try ToolLimits.truncate(Yams.dump(object: object))
    }

    private func tomlToJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        let table = try TOMLTable(string: text)
        return ToolLimits.truncate(table.convert(to: .json))
    }

    private func jsonToTOML(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
        guard let dict = object as? [String: Any] else {
            throw ToolError.invalidInput("JSON root must be an object for TOML conversion.")
        }
        let table = try jsonDictionaryToTOMLTable(dict)
        return ToolLimits.truncate(table.convert(to: .toml))
    }

    private func jsonDictionaryToTOMLTable(_ dict: [String: Any]) throws -> TOMLTable {
        let table = TOMLTable()
        for (key, value) in dict {
            table[key] = try jsonToTOMLValue(value)
        }
        return table
    }

    private func jsonToTOMLValue(_ value: Any) throws -> TOMLValueConvertible {
        switch value {
        case is NSNull:
            throw ToolError.invalidInput("TOML does not support null values.")
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            if number.doubleValue.rounded() == number.doubleValue,
               let int = Int(exactly: number.int64Value) {
                return int
            }
            return number.doubleValue
        case let array as [Any]:
            return TOMLArray(try array.map { try jsonToTOMLValue($0) })
        case let dict as [String: Any]:
            return try jsonDictionaryToTOMLTable(dict)
        default:
            throw ToolError.invalidInput("Unsupported JSON value for TOML: \(type(of: value))")
        }
    }

    private func sanitizeJSONObject(_ value: Any) -> Any {
        switch value {
        case let dict as [AnyHashable: Any]:
            var out: [String: Any] = [:]
            for (key, nested) in dict {
                out[String(describing: key)] = sanitizeJSONObject(nested)
            }
            return out
        case let array as [Any]:
            return array.map(sanitizeJSONObject)
        case is NSNull, is String, is Bool, is NSNumber:
            return value
        default:
            return String(describing: value)
        }
    }

    private func iniToJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        var root: [String: [String: String]] = [:]
        var section = "default"
        root[section] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                root[section] = root[section] ?? [:]
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            root[section, default: [:]][parts[0]] = parts[1]
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func decodeBSON(_ text: String) throws -> String {
        let data = try BinaryCodec.decodeData(text)
        guard data.count >= 5 else { throw ToolError.invalidInput("BSON document too short.") }
        let length = data.withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        guard Int(length) == data.count else {
            throw ToolError.invalidInput("BSON length mismatch (\(length) vs \(data.count)).")
        }
        let document = Document(data: data)
        let jsonObject = bsonPrimitiveToJSON(document)
        let jsonData = try JSONSerialization.data(
            withJSONObject: jsonObject,
            options: [.prettyPrinted, .sortedKeys]
        )
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw ToolError.failed("Could not encode BSON as JSON.")
        }
        return json
    }

    private func bsonPrimitiveToJSON(_ value: Primitive) -> Any {
        switch value {
        case let document as Document:
            if document.isArray {
                return document.values.map { bsonPrimitiveToJSON($0) }
            }
            var object: [String: Any] = [:]
            for pair in document.pairs {
                object[pair.key] = bsonPrimitiveToJSON(pair.value)
            }
            return object
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let int32 as Int32:
            return Int(int32)
        case let double as Double:
            return double
        case is Null:
            return NSNull()
        case let objectId as ObjectId:
            return ["$oid": objectId.hexString]
        case let date as Date:
            return ["$date": ISO8601DateFormatter().string(from: date)]
        case let binary as Binary:
            return ["$binary": binary.data.base64EncodedString()]
        default:
            if let number = value as? any BinaryInteger {
                return Int(number)
            }
            return String(describing: value)
        }
    }

    private func decodeMessagePack(_ text: String) throws -> String {
        let data = try BinaryCodec.decodeData(text)
        let value = try MessagePack.decode(data)
        return try value.encode(pretty: true)
    }

    private func prettyNDJSON(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        var lines: [String] = []
        var index = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            index += 1
            let pretty = try JSONValue.parse(line).encode(pretty: true)
            lines.append("// line \(index)\n\(pretty)")
        }
        return ToolLimits.truncate(lines.joined(separator: "\n\n"))
    }

    private func fakeJSON(from text: String, count: Int) throws -> String {
        let sample: JSONValue
        if let parsed = try? JSONValue.parse(text), case .object = parsed {
            if let type = (parsed.toAny() as? [String: Any])?["type"] as? String, type == "object" {
                sample = synthesize(fromSchema: parsed.toAny() as? [String: Any] ?? [:])
            } else {
                sample = parsed
            }
        } else {
            sample = .object([
                ("id", .string(UUID().uuidString)),
                ("name", .string("Item")),
                ("active", .bool(true)),
                ("score", .number(Double.random(in: 0...100))),
            ])
        }
        let items = (0..<count).map { index -> JSONValue in
            mutate(sample, index: index)
        }
        return try JSONValue.array(items).encode(pretty: true)
    }

    private func synthesize(fromSchema schema: [String: Any]) -> JSONValue {
        let type = schema["type"] as? String ?? "string"
        switch type {
        case "object":
            let props = schema["properties"] as? [String: Any] ?? [:]
            let pairs = props.keys.sorted().map { key -> (String, JSONValue) in
                let child = props[key] as? [String: Any] ?? ["type": "string"]
                return (key, synthesize(fromSchema: child))
            }
            return .object(pairs)
        case "array":
            let items = schema["items"] as? [String: Any] ?? ["type": "string"]
            return .array([synthesize(fromSchema: items)])
        case "number", "integer": return .number(42)
        case "boolean": return .bool(true)
        case "null": return .null
        default: return .string("sample")
        }
    }

    private func mutate(_ value: JSONValue, index: Int) -> JSONValue {
        switch value {
        case .string(let s):
            if s.contains("-"), UUID(uuidString: s) != nil { return .string(UUID().uuidString) }
            return .string("\(s)-\(index + 1)")
        case .number: return .number(Double(index + 1))
        case .bool(let b): return .bool(index.isMultiple(of: 2) ? b : !b)
        case .array(let a): return .array(a.map { mutate($0, index: index) })
        case .object(let o): return .object(o.map { ($0.0, mutate($0.1, index: index)) })
        case .null: return .null
        }
    }
}

private final class SimpleXMLParser: NSObject, XMLParserDelegate {
    private var stack: [(name: String, children: [String: [JSONValue]], text: String)] = []
    private var root: JSONValue?
    private var error: String?

    func parse(_ text: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw ToolError.invalidInput("XML is not UTF-8.")
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse(), let root else {
            throw ToolError.invalidInput(error ?? parser.parserError?.localizedDescription ?? "Invalid XML.")
        }
        return root
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        var children: [String: [JSONValue]] = [:]
        for (key, value) in attributeDict {
            children["@" + key] = [.string(value)]
        }
        stack.append((elementName, children, ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let current = stack.popLast() else { return }
        let trimmed = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: JSONValue
        if current.children.isEmpty {
            value = .string(trimmed)
        } else {
            var object: [(String, JSONValue)] = []
            for key in current.children.keys.sorted() {
                let values = current.children[key] ?? []
                if values.count == 1 {
                    object.append((key, values[0]))
                } else {
                    object.append((key, .array(values)))
                }
            }
            if !trimmed.isEmpty { object.append(("#text", .string(trimmed))) }
            value = .object(object)
        }
        if stack.isEmpty {
            root = .object([(current.name, value)])
        } else {
            stack[stack.count - 1].children[current.name, default: []].append(value)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError.localizedDescription
    }
}

enum SimpleYAML {
    static func parse(_ text: String) throws -> JSONValue {
        var lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map(String.init)
        return try parseBlock(&lines, indent: 0)
    }

    private static func parseBlock(_ lines: inout [String], indent: Int) throws -> JSONValue {
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty
            || first.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        {
            lines.removeFirst()
        }
        guard let first = lines.first else { return .null }
        let currentIndent = leadingSpaces(first)
        if currentIndent < indent { return .null }
        if first.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
            var items: [JSONValue] = []
            while let line = lines.first {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") {
                    lines.removeFirst()
                    continue
                }
                let spaces = leadingSpaces(line)
                if spaces < indent { break }
                if spaces > indent {
                    throw ToolError.invalidInput("Unexpected nested YAML indentation.")
                }
                guard trimmed.hasPrefix("- ") else { break }
                lines.removeFirst()
                let rest = String(trimmed.dropFirst(2))
                if rest.contains(":"), !rest.hasPrefix("{"), !rest.hasPrefix("[") {
                    lines.insert(String(repeating: " ", count: indent + 2) + rest, at: 0)
                    items.append(try parseBlock(&lines, indent: indent + 2))
                } else {
                    items.append(try parseScalar(rest))
                }
            }
            return .array(items)
        }
        var object: [(String, JSONValue)] = []
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                lines.removeFirst()
                continue
            }
            let spaces = leadingSpaces(line)
            if spaces < indent { break }
            if spaces > indent {
                throw ToolError.invalidInput("Unexpected nested YAML indentation.")
            }
            if trimmed.hasPrefix("- ") { break }
            lines.removeFirst()
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count >= 1 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let valuePart = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            if valuePart.isEmpty {
                object.append((key, try parseBlock(&lines, indent: indent + 2)))
            } else {
                object.append((key, try parseScalar(valuePart)))
            }
        }
        return .object(object)
    }

    private static func parseScalar(_ text: String) throws -> JSONValue {
        if text == "null" || text == "~" { return .null }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let number = Double(text) { return .number(number) }
        if (text.hasPrefix("\"") && text.hasSuffix("\""))
            || (text.hasPrefix("'") && text.hasSuffix("'"))
        {
            return .string(String(text.dropFirst().dropLast()))
        }
        return .string(text)
    }

    private static func leadingSpaces(_ line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    static func dump(_ value: JSONValue, indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return String(n)
        case .string(let s):
            if s.contains(":") || s.contains("#") || s.contains("\n") {
                return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
            }
            return s
        case .array(let items):
            if items.isEmpty { return "[]" }
            return items.map { item in
                let body = dump(item, indent: indent + 1)
                if case .object = item {
                    return "\(pad)- \n" + body.split(separator: "\n").map { "\(pad)  \($0)" }.joined(separator: "\n")
                }
                return "\(pad)- \(body)"
            }.joined(separator: "\n")
        case .object(let pairs):
            if pairs.isEmpty { return "{}" }
            return pairs.map { key, child in
                switch child {
                case .array, .object:
                    return "\(pad)\(key):\n\(dump(child, indent: indent + 1))"
                default:
                    return "\(pad)\(key): \(dump(child, indent: 0))"
                }
            }.joined(separator: "\n")
        }
    }
}

enum SimpleTOML {
    static func parse(_ text: String) throws -> JSONValue {
        var root: [String: JSONValue] = [:]
        var currentPath: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                let name = String(line.dropFirst().dropLast())
                currentPath = name.split(separator: ".").map(String.init)
                ensurePath(&root, currentPath)
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = try parseValue(parts[1])
            set(&root, path: currentPath + [key], value: value)
        }
        return .object(root.keys.sorted().map { ($0, root[$0]!) })
    }

    private static func parseValue(_ text: String) throws -> JSONValue {
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let n = Double(text) { return .number(n) }
        if text.hasPrefix("\""), text.hasSuffix("\"") {
            return .string(String(text.dropFirst().dropLast()))
        }
        return .string(text)
    }

    private static func ensurePath(_ root: inout [String: JSONValue], _ path: [String]) {
        guard let first = path.first else { return }
        if root[first] == nil { root[first] = .object([]) }
        guard path.count > 1, case .object(let pairs) = root[first] else { return }
        var child = Dictionary(uniqueKeysWithValues: pairs)
        ensurePath(&child, Array(path.dropFirst()))
        root[first] = .object(child.keys.sorted().map { ($0, child[$0]!) })
    }

    private static func set(_ root: inout [String: JSONValue], path: [String], value: JSONValue) {
        guard let first = path.first else { return }
        if path.count == 1 {
            root[first] = value
            return
        }
        var child: [String: JSONValue] = [:]
        if case .object(let pairs) = root[first] {
            child = Dictionary(uniqueKeysWithValues: pairs)
        }
        set(&child, path: Array(path.dropFirst()), value: value)
        root[first] = .object(child.keys.sorted().map { ($0, child[$0]!) })
    }

    static func dump(_ value: JSONValue) -> String {
        guard case .object(let pairs) = value else {
            return "# root must be a table\nvalue = \(scalar(value))\n"
        }
        var lines: [String] = []
        var tables: [(String, JSONValue)] = []
        for (key, child) in pairs {
            if case .object = child {
                tables.append((key, child))
            } else {
                lines.append("\(key) = \(scalar(child))")
            }
        }
        for (name, table) in tables {
            lines.append("")
            lines.append("[\(name)]")
            if case .object(let children) = table {
                for (key, child) in children {
                    lines.append("\(key) = \(scalar(child))")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func scalar(_ value: JSONValue) -> String {
        switch value {
        case .null: return "\"null\""
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return String(n)
        case .string(let s): return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
        case .array(let a): return "[\(a.map(scalar).joined(separator: ", "))]"
        case .object: return "\"[table]\""
        }
    }
}

enum BinaryCodec {
    static func decodeData(_ text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Data(base64Encoded: trimmed) { return data }
        let hex = trimmed.replacingOccurrences(of: " ", with: "")
        guard hex.count.isMultiple(of: 2), hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            throw ToolError.invalidInput("Provide hex or base64.")
        }
        var data = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let byte = String(hex[index..<next])
            data.append(UInt8(byte, radix: 16)!)
            index = next
        }
        return data
    }
}

enum MessagePack {
    static func decode(_ data: Data) throws -> JSONValue {
        var offset = 0
        let value = try read(data, offset: &offset)
        return value
    }

    private static func read(_ data: Data, offset: inout Int) throws -> JSONValue {
        guard offset < data.count else { throw ToolError.invalidInput("Truncated MessagePack.") }
        let byte = data[offset]
        offset += 1
        switch byte {
        case 0x00...0x7f: return .number(Double(byte))
        case 0xc0: return .null
        case 0xc2: return .bool(false)
        case 0xc3: return .bool(true)
        case 0xcc:
            return .number(Double(try readUInt8(data, &offset)))
        case 0xcd:
            return .number(Double(try readUInt16(data, &offset)))
        case 0xce:
            return .number(Double(try readUInt32(data, &offset)))
        case 0xcf:
            return .number(Double(try readUInt64(data, &offset)))
        case 0xd0:
            return .number(Double(Int8(bitPattern: try readUInt8(data, &offset))))
        case 0xd1:
            return .number(Double(Int16(bitPattern: try readUInt16(data, &offset))))
        case 0xd2:
            return .number(Double(Int32(bitPattern: try readUInt32(data, &offset))))
        case 0xd3:
            return .number(Double(Int64(bitPattern: try readUInt64(data, &offset))))
        case 0xca:
            let be = try readUInt32(data, &offset)
            return .number(Double(Float(bitPattern: be)))
        case 0xcb:
            let be = try readUInt64(data, &offset)
            return .number(Double(bitPattern: be))
        case 0xa0...0xbf:
            let length = Int(byte - 0xa0)
            return .string(try readString(data, &offset, length))
        case 0xd9:
            let length = Int(try readUInt8(data, &offset))
            return .string(try readString(data, &offset, length))
        case 0xda:
            let length = Int(try readUInt16(data, &offset))
            return .string(try readString(data, &offset, length))
        case 0xdb:
            let length = Int(try readUInt32(data, &offset))
            return .string(try readString(data, &offset, length))
        case 0xc4:
            let length = Int(try readUInt8(data, &offset))
            return .string(try readBinary(data, &offset, length))
        case 0xc5:
            let length = Int(try readUInt16(data, &offset))
            return .string(try readBinary(data, &offset, length))
        case 0xc6:
            let length = Int(try readUInt32(data, &offset))
            return .string(try readBinary(data, &offset, length))
        case 0xc7:
            let length = Int(try readUInt8(data, &offset))
            _ = try readUInt8(data, &offset) // ext type
            return .string(try readBinary(data, &offset, length))
        case 0xc8:
            let length = Int(try readUInt16(data, &offset))
            _ = try readUInt8(data, &offset)
            return .string(try readBinary(data, &offset, length))
        case 0xc9:
            let length = Int(try readUInt32(data, &offset))
            _ = try readUInt8(data, &offset)
            return .string(try readBinary(data, &offset, length))
        case 0xd4...0xd8:
            let length: Int = {
                switch byte {
                case 0xd4: return 1
                case 0xd5: return 2
                case 0xd6: return 4
                case 0xd7: return 8
                default: return 16
                }
            }()
            _ = try readUInt8(data, &offset)
            return .string(try readBinary(data, &offset, length))
        case 0x90...0x9f:
            let count = Int(byte - 0x90)
            return .array(try (0..<count).map { _ in try read(data, offset: &offset) })
        case 0xdc:
            let count = Int(try readUInt16(data, &offset))
            return .array(try (0..<count).map { _ in try read(data, offset: &offset) })
        case 0xdd:
            let count = Int(try readUInt32(data, &offset))
            return .array(try (0..<count).map { _ in try read(data, offset: &offset) })
        case 0x80...0x8f:
            let count = Int(byte - 0x80)
            return .object(try readMap(data, &offset, count: count))
        case 0xde:
            let count = Int(try readUInt16(data, &offset))
            return .object(try readMap(data, &offset, count: count))
        case 0xdf:
            let count = Int(try readUInt32(data, &offset))
            return .object(try readMap(data, &offset, count: count))
        case 0xe0...0xff:
            return .number(Double(Int8(bitPattern: byte)))
        default:
            throw ToolError.invalidInput(String(format: "Unsupported MessagePack byte 0x%02x.", byte))
        }
    }

    private static func readMap(_ data: Data, _ offset: inout Int, count: Int) throws -> [(String, JSONValue)] {
        var pairs: [(String, JSONValue)] = []
        for _ in 0..<count {
            let keyValue = try read(data, offset: &offset)
            let key: String
            switch keyValue {
            case .string(let s): key = s
            case .number(let n): key = String(n)
            default:
                throw ToolError.invalidInput("MessagePack map key must be string or number.")
            }
            pairs.append((key, try read(data, offset: &offset)))
        }
        return pairs
    }

    private static func readBinary(_ data: Data, _ offset: inout Int, _ length: Int) throws -> String {
        guard offset + length <= data.count else { throw ToolError.invalidInput("Truncated binary.") }
        let slice = data[offset..<(offset + length)]
        offset += length
        return "base64:" + Data(slice).base64EncodedString()
    }

    private static func readUInt8(_ data: Data, _ offset: inout Int) throws -> UInt8 {
        guard offset < data.count else { throw ToolError.invalidInput("Truncated MessagePack.") }
        defer { offset += 1 }
        return data[offset]
    }

    private static func readUInt16(_ data: Data, _ offset: inout Int) throws -> UInt16 {
        let b0 = UInt16(try readUInt8(data, &offset))
        let b1 = UInt16(try readUInt8(data, &offset))
        return (b0 << 8) | b1
    }

    private static func readUInt32(_ data: Data, _ offset: inout Int) throws -> UInt32 {
        let b0 = UInt32(try readUInt8(data, &offset))
        let b1 = UInt32(try readUInt8(data, &offset))
        let b2 = UInt32(try readUInt8(data, &offset))
        let b3 = UInt32(try readUInt8(data, &offset))
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }

    private static func readUInt64(_ data: Data, _ offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 {
            value = (value << 8) | UInt64(try readUInt8(data, &offset))
        }
        return value
    }

    private static func readString(_ data: Data, _ offset: inout Int, _ length: Int) throws -> String {
        guard offset + length <= data.count else { throw ToolError.invalidInput("Truncated string.") }
        let slice = data[offset..<(offset + length)]
        offset += length
        return String(data: slice, encoding: .utf8) ?? slice.map { String(format: "%02x", $0) }.joined()
    }
}

enum JSONPath {
    static func query(document: String, path: String) throws -> String {
        let root = try JSONValue.parse(document)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else {
            throw ToolError.invalidInput("JSONPath must start with $.")
        }
        var current: [JSONValue] = [root]
        var token = ""
        var i = trimmed.index(after: trimmed.startIndex)
        func flush() {
            let name = token
            token = ""
            guard !name.isEmpty else { return }
            current = current.flatMap { value -> [JSONValue] in
                if name == "*" {
                    switch value {
                    case .object(let o): return o.map(\.1)
                    case .array(let a): return a
                    default: return []
                    }
                }
                if name.hasPrefix("["), name.hasSuffix("]") {
                    let inner = String(name.dropFirst().dropLast())
                    if inner == "*" {
                        if case .array(let a) = value { return a }
                        return []
                    }
                    if let index = Int(inner), case .array(let a) = value, a.indices.contains(index) {
                        return [a[index]]
                    }
                    return []
                }
                if case .object(let o) = value {
                    return o.filter { $0.0 == name }.map(\.1)
                }
                return []
            }
        }
        while i < trimmed.endIndex {
            let c = trimmed[i]
            if c == "." {
                flush()
            } else if c == "[" {
                flush()
                var bracket = "["
                i = trimmed.index(after: i)
                while i < trimmed.endIndex {
                    bracket.append(trimmed[i])
                    if trimmed[i] == "]" { break }
                    i = trimmed.index(after: i)
                }
                token = bracket
                flush()
            } else {
                token.append(c)
            }
            i = trimmed.index(after: i)
        }
        flush()
        return try JSONValue.array(current).encode(pretty: true)
    }
}

