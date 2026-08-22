import Foundation

enum NumberCrunchError: LocalizedError, Equatable {
    case emptySelection
    case noNumbers
    case invalidExpression
    case noUnits
    case noByteUnits
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select some numbers first."
        case .noNumbers:
            return "No numbers were found in the selection."
        case .invalidExpression:
            return "That does not look like a math expression."
        case .noUnits:
            return "No convertible units were found in the selection."
        case .noByteUnits:
            return "No file sizes were found in the selection."
        case .unknownAction(let id):
            return "Unknown Number Crunch action “\(id)”."
        }
    }
}

enum NumberCrunchEngine {
    static func sum(_ text: String) throws -> String {
        let values = try numbers(in: text)
        return format(values.reduce(0, +))
    }

    static func average(_ text: String) throws -> String {
        let values = try numbers(in: text)
        return format(values.reduce(0, +) / Double(values.count))
    }

    static func evaluate(_ text: String) throws -> String {
        let source = try nonempty(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let expression = source
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        var parser = ExpressionParser(expression)
        let value = try parser.parse()
        return "\(source) = \(format(value))"
    }

    static func convert(_ text: String, to system: UnitSystem) throws -> String {
        let source = try nonempty(text)
        var output = ""
        var current = source.startIndex
        var converted = 0
        while current < source.endIndex {
            if let match = nextQuantity(in: source, from: current),
               let replacement = convert(match, to: system) {
                converted += 1
                output += source[current..<match.range.lowerBound]
                output += replacement
                current = match.range.upperBound
            } else if let match = nextQuantity(in: source, from: current) {
                output += source[current..<match.range.upperBound]
                current = match.range.upperBound
            } else {
                output += source[current...]
                break
            }
        }
        guard converted > 0 else { throw NumberCrunchError.noUnits }
        return output
    }

    static func humanizeSizes(_ text: String) throws -> String {
        try replaceByteQuantities(text) { match in
            formatByteSize(match.bytes, style: .human)
        }
    }

    static func toBytes(_ text: String) throws -> String {
        try replaceByteQuantities(text) { match in
            formatByteSize(match.bytes, style: .bytes)
        }
    }

    static func numbers(in text: String) throws -> [Double] {
        let source = try nonempty(text)
        let matches = source.matches(of: /-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?/)
        let values = matches.compactMap { match -> Double? in
            Double(String(match.0).replacingOccurrences(of: ",", with: ""))
        }
        guard !values.isEmpty else { throw NumberCrunchError.noNumbers }
        return values
    }

    private static func replaceByteQuantities(
        _ text: String,
        transform: (ByteMatch) -> String
    ) throws -> String {
        let source = try nonempty(text)
        if let lone = loneByteCount(in: source) {
            return transform(lone)
        }

        var output = ""
        var current = source.startIndex
        var converted = 0
        while current < source.endIndex {
            if let match = nextByteQuantity(in: source, from: current) {
                converted += 1
                output += source[current..<match.range.lowerBound]
                output += transform(match)
                current = match.range.upperBound
            } else {
                output += source[current...]
                break
            }
        }
        guard converted > 0 else { throw NumberCrunchError.noByteUnits }
        return output
    }

    private static func loneByteCount(in text: String) -> ByteMatch? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(
            of: /-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?/
        ),
        let value = Double(String(match.0).replacingOccurrences(of: ",", with: "")) else {
            return nil
        }
        return ByteMatch(range: text.startIndex..<text.endIndex, bytes: value)
    }

    private static func nextByteQuantity(in text: String, from start: String.Index) -> ByteMatch? {
        guard start < text.endIndex else { return nil }
        let slice = text[start...]
        let pattern = /(?i)(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?)\s*(pebibytes?|petabytes?|tibibytes?|terabytes?|gibibytes?|gigabytes?|mebibytes?|megabytes?|kibibytes?|kilobytes?|pib|tib|gib|mib|kib|pb|tb|gb|mb|kb|bytes?|bits?|b)\b/
        guard let match = slice.firstMatch(of: pattern) else { return nil }
        let rawValue = String(match.1).replacingOccurrences(of: ",", with: "")
        let skip = text.index(
            start,
            offsetBy: slice.distance(from: slice.startIndex, to: match.range.upperBound)
        )
        guard let value = Double(rawValue),
              let unit = ByteUnit(token: String(match.2)) else {
            return nextByteQuantity(in: text, from: skip)
        }
        let lower = text.index(start, offsetBy: slice.distance(from: slice.startIndex, to: match.range.lowerBound))
        return ByteMatch(range: lower..<skip, bytes: value * unit.bytes)
    }

    private static func formatByteSize(_ bytes: Double, style: ByteFormat) -> String {
        switch style {
        case .bytes:
            return "\(format(bytes)) B"
        case .human:
            let magnitude = abs(bytes)
            let units: [(Double, String)] = [
                (pow(1024, 5), "PiB"),
                (pow(1024, 4), "TiB"),
                (pow(1024, 3), "GiB"),
                (pow(1024, 2), "MiB"),
                (1024, "KiB"),
            ]
            for (factor, name) in units where magnitude >= factor {
                return "\(format(bytes / factor)) \(name)"
            }
            return "\(format(bytes)) B"
        }
    }

    private static func nonempty(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NumberCrunchError.emptySelection
        }
        return text
    }

    private static func nextQuantity(in text: String, from start: String.Index) -> QuantityMatch? {
        guard start < text.endIndex else { return nil }
        let slice = text[start...]
        let pattern = /(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?)\s*(°F|°C|deg(?:rees?)?\s*F|deg(?:rees?)?\s*C|fahrenheit|celsius|kilometers?|kilometres?|km|miles?|mi|kilograms?|kg|pounds?|lbs?|ounces?|oz|grams?|g|yards?|yd|feet|foot|ft|inches|inch|millimeters?|millimetres?|mm|centimeters?|centimetres?|cm|meters?|metres?|m)\b/
        guard let match = slice.firstMatch(of: pattern) else { return nil }
        let rawValue = String(match.1).replacingOccurrences(of: ",", with: "")
        guard let value = Double(rawValue),
              let unit = MeasureUnit(token: String(match.2)) else {
            let skip = text.index(
                start,
                offsetBy: slice.distance(from: slice.startIndex, to: match.range.upperBound)
            )
            return nextQuantity(in: text, from: skip)
        }
        let lower = text.index(start, offsetBy: slice.distance(from: slice.startIndex, to: match.range.lowerBound))
        let upper = text.index(start, offsetBy: slice.distance(from: slice.startIndex, to: match.range.upperBound))
        return QuantityMatch(range: lower..<upper, value: value, unit: unit)
    }

    private static func convert(_ match: QuantityMatch, to system: UnitSystem) -> String? {
        guard match.unit.system != system,
              let converted = match.unit.convert(match.value, to: system) else {
            return nil
        }
        return "\(format(converted.value)) \(converted.unit.displayName)"
    }

    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "∞" }
        if abs(value - value.rounded()) < 1e-9, abs(value) < 1e12 {
            return String(Int(value.rounded()))
        }
        var output = String(format: "%.4f", value)
        while output.hasSuffix("0") { output.removeLast() }
        if output.hasSuffix(".") { output.removeLast() }
        return output
    }
}

enum UnitSystem: Sendable {
    case metric
    case imperial
}

private struct QuantityMatch {
    let range: Range<String.Index>
    let value: Double
    let unit: MeasureUnit
}

private struct ByteMatch {
    let range: Range<String.Index>
    let bytes: Double
}

private enum ByteFormat {
    case bytes
    case human
}

private enum ByteUnit {
    case bit, byte
    case kilobyte, megabyte, gigabyte, terabyte, petabyte
    case kibibyte, mebibyte, gibibyte, tebibyte, pebibyte

    var bytes: Double {
        switch self {
        case .bit: 1 / 8
        case .byte: 1
        case .kilobyte: 1_000
        case .megabyte: 1_000_000
        case .gigabyte: 1_000_000_000
        case .terabyte: 1_000_000_000_000
        case .petabyte: 1_000_000_000_000_000
        case .kibibyte: 1_024
        case .mebibyte: pow(1024, 2)
        case .gibibyte: pow(1024, 3)
        case .tebibyte: pow(1024, 4)
        case .pebibyte: pow(1024, 5)
        }
    }

    init?(token: String) {
        switch token.lowercased() {
        case "b", "byte", "bytes": self = .byte
        case "bit", "bits": self = .bit
        case "kb", "kilobyte", "kilobytes": self = .kilobyte
        case "mb", "megabyte", "megabytes": self = .megabyte
        case "gb", "gigabyte", "gigabytes": self = .gigabyte
        case "tb", "terabyte", "terabytes": self = .terabyte
        case "pb", "petabyte", "petabytes": self = .petabyte
        case "kib", "kibibyte", "kibibytes": self = .kibibyte
        case "mib", "mebibyte", "mebibytes": self = .mebibyte
        case "gib", "gibibyte", "gibibytes": self = .gibibyte
        case "tib", "tebibyte", "tebibytes", "tibibyte", "tibibytes": self = .tebibyte
        case "pib", "pebibyte", "pebibytes": self = .pebibyte
        default: return nil
        }
    }
}

private enum MeasureUnit: Sendable {
    case kilogram, gram, pound, ounce
    case kilometer, meter, centimeter, millimeter, mile, foot, yard, inch
    case celsius, fahrenheit

    var system: UnitSystem {
        switch self {
        case .kilogram, .gram, .kilometer, .meter, .centimeter, .millimeter, .celsius:
            return .metric
        case .pound, .ounce, .mile, .foot, .yard, .inch, .fahrenheit:
            return .imperial
        }
    }

    var displayName: String {
        switch self {
        case .kilogram: "kg"
        case .gram: "g"
        case .pound: "lb"
        case .ounce: "oz"
        case .kilometer: "km"
        case .meter: "m"
        case .centimeter: "cm"
        case .millimeter: "mm"
        case .mile: "mi"
        case .foot: "ft"
        case .yard: "yd"
        case .inch: "in"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        }
    }

    init?(token: String) {
        switch token.lowercased().replacingOccurrences(of: " ", with: "") {
        case "kg", "kilogram", "kilograms": self = .kilogram
        case "g", "gram", "grams": self = .gram
        case "lb", "lbs", "pound", "pounds": self = .pound
        case "oz", "ounce", "ounces": self = .ounce
        case "km", "kilometer", "kilometers", "kilometre", "kilometres": self = .kilometer
        case "m", "meter", "meters", "metre", "metres": self = .meter
        case "cm", "centimeter", "centimeters", "centimetre", "centimetres": self = .centimeter
        case "mm", "millimeter", "millimeters", "millimetre", "millimetres": self = .millimeter
        case "mi", "mile", "miles": self = .mile
        case "ft", "foot", "feet": self = .foot
        case "yd", "yard", "yards": self = .yard
        case "inch", "inches": self = .inch
        case "°c", "celsius", "degc", "degreec", "degreesc": self = .celsius
        case "°f", "fahrenheit", "degf", "degreef", "degreesf": self = .fahrenheit
        default: return nil
        }
    }

    func convert(_ value: Double, to system: UnitSystem) -> (value: Double, unit: MeasureUnit)? {
        switch (self, system) {
        case (.pound, .metric): return (value * 0.45359237, .kilogram)
        case (.ounce, .metric): return (value * 28.349523125, .gram)
        case (.kilogram, .imperial): return (value / 0.45359237, .pound)
        case (.gram, .imperial): return (value / 28.349523125, .ounce)
        case (.mile, .metric): return (value * 1.609344, .kilometer)
        case (.foot, .metric): return (value * 0.3048, .meter)
        case (.yard, .metric): return (value * 0.9144, .meter)
        case (.inch, .metric): return (value * 2.54, .centimeter)
        case (.kilometer, .imperial): return (value / 1.609344, .mile)
        case (.meter, .imperial): return (value / 0.3048, .foot)
        case (.centimeter, .imperial): return (value / 2.54, .inch)
        case (.millimeter, .imperial): return (value / 25.4, .inch)
        case (.fahrenheit, .metric): return ((value - 32) * 5 / 9, .celsius)
        case (.celsius, .imperial): return (value * 9 / 5 + 32, .fahrenheit)
        default: return nil
        }
    }
}

private struct ExpressionParser {
    private let tokens: [Token]
    private var index = 0

    enum Token: Equatable {
        case number(Double)
        case plus, minus, star, slash, caret, lparen, rparen
    }

    init(_ source: String) {
        tokens = Self.tokenize(source)
    }

    mutating func parse() throws -> Double {
        let value = try expression()
        guard index >= tokens.count else { throw NumberCrunchError.invalidExpression }
        return value
    }

    private mutating func expression() throws -> Double {
        var value = try term()
        while match(.plus) || match(.minus) {
            let op = tokens[index - 1]
            let rhs = try term()
            value = op == .plus ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func term() throws -> Double {
        var value = try power()
        while match(.star) || match(.slash) {
            let op = tokens[index - 1]
            let rhs = try power()
            value = op == .star ? value * rhs : value / rhs
        }
        return value
    }

    private mutating func power() throws -> Double {
        let value = try unary()
        if match(.caret) {
            return pow(value, try power())
        }
        return value
    }

    private mutating func unary() throws -> Double {
        if match(.minus) { return -(try unary()) }
        if match(.plus) { return try unary() }
        return try primary()
    }

    private mutating func primary() throws -> Double {
        if case .number(let value) = peek() {
            index += 1
            return value
        }
        if match(.lparen) {
            let value = try expression()
            guard match(.rparen) else { throw NumberCrunchError.invalidExpression }
            return value
        }
        throw NumberCrunchError.invalidExpression
    }

    private func peek() -> Token? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func match(_ token: Token) -> Bool {
        guard peek() == token else { return false }
        index += 1
        return true
    }

    private static func tokenize(_ source: String) -> [Token] {
        var tokens: [Token] = []
        var current = source.startIndex
        while current < source.endIndex {
            let character = source[current]
            if character.isWhitespace {
                current = source.index(after: current)
                continue
            }
            if character.isNumber || character == "." {
                let remaining = source[current...]
                if let match = remaining.prefixMatch(of: /\d+(?:\.\d+)?|\.\d+/) {
                    if let value = Double(String(match.0)) {
                        tokens.append(.number(value))
                    }
                    current = match.range.upperBound
                    continue
                }
            }
            switch character {
            case "+": tokens.append(.plus)
            case "-": tokens.append(.minus)
            case "*": tokens.append(.star)
            case "/": tokens.append(.slash)
            case "^": tokens.append(.caret)
            case "(": tokens.append(.lparen)
            case ")": tokens.append(.rparen)
            default: return []
            }
            current = source.index(after: current)
        }
        return tokens
    }
}
