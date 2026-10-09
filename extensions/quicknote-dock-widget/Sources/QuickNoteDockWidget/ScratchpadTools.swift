import Foundation
import Vision

struct ScratchAnalysis: Equatable, Sendable {
    var mode = "text"
    var results: [String] = []
    var summary = ""
    var source = ""
    var mathResults: [ScratchMathResult] = []
    /// A `math` section exists somewhere in the note, so answers draw inline.
    var inlineMath = false
    var checkboxes: [NoteCheckbox] = []
    var spans: [ScratchTextSpan] = []
    var prepared = false
    var cacheCost = 0
}

/// Text drawn after a line without changing the note: a math answer, a
/// section total, or a dimmed hint saying what an empty section expects.
struct ScratchMathResult: Equatable, Sendable {
    let range: NSRange
    let answer: String
    var isHint = false
}

enum ScratchMode {
    static let all = ["math", "sum", "average", "count", "list", "code", "text"]

    /// The keyword before an optional `: title` on the first line, or "" when
    /// the note does not start with one. Editor styling, checkbox parsing and
    /// analysis must all agree, so "Codename ideas" is never a code note.
    static func keyword(of text: String) -> String {
        let first = text.prefix { !$0.isNewline }.lowercased()
        let keyword = first.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return all.contains(keyword) ? keyword : ""
    }

    struct Line: Equatable, Sendable {
        var number: Int
        /// The line without its newline, in UTF-16 offsets.
        var range: NSRange
    }

    struct Section: Equatable, Sendable {
        var mode: String
        var title: String
        /// The keyword on the first line applies to the whole note.
        var wholeNote: Bool
        /// The heading line, and its keyword up to and including any colon.
        var header: NSRange
        var keyword: NSRange
        var lines: [Line] = []
    }

    /// Splits a note into keyword sections. A keyword on the first line applies
    /// to every line that is not in another section. Elsewhere, a line holding
    /// only a keyword (or `keyword: title`) starts a section that ends at the
    /// next blank line, so `/list` in the middle of a note changes only what
    /// follows it. `text` ends a section early.
    static func sections(in text: String) -> [Section] {
        var note: Section?
        var blocks: [Section] = []
        var block: Section?
        var offset = 0
        for (number, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            defer { offset += raw.utf16.count + 1 }
            let range = NSRange(location: offset, length: line.utf16.count)
            let mode = keyword(of: line)
            if !mode.isEmpty {
                if let block { blocks.append(block) }
                block = nil
                let colon = line.firstIndex(of: ":")
                let title = colon.map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                let indent = line.prefix { $0 == " " || $0 == "\t" }.utf16.count
                let end = colon.map { line[...$0].utf16.count } ?? line.trimmingCharacters(in: .whitespaces).utf16.count + indent
                let keywordRange = NSRange(location: offset + indent, length: end - indent)
                if mode != "text" {
                    let section = Section(mode: mode, title: title, wholeNote: number == 0, header: range, keyword: keywordRange)
                    if number == 0 { note = section } else { block = section }
                }
                continue
            }
            if block != nil, line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(block!); block = nil
                continue
            }
            if block != nil { block!.lines.append(Line(number: number + 1, range: range)) }
            else { note?.lines.append(Line(number: number + 1, range: range)) }
        }
        if let block { blocks.append(block) }
        return (note.map { [$0] } ?? []) + blocks
    }
}

actor ScratchTools {
    func search(_ notes: [ScratchNote], query: String, scope: String) throws -> [String] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try notes.filter { note in
            try Task.checkCancellation()
            let included = scope == "void" ? note.deleted != nil : note.deleted == nil && (scope == "slots" ? note.slot != nil : note.slot == nil)
            return included && (needle.isEmpty || note.content.localizedCaseInsensitiveContains(needle))
        }
        return (scope == "slots" ? result.sorted { ($0.slot ?? 0) < ($1.slot ?? 0) } : result).map(\.id)
    }

    func matchingNotes(_ notes: [ScratchNote], ids: [String]) -> [ScratchNote] {
        let index = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        return ids.compactMap { index[$0] }
    }

    func analyze(_ text: String) throws -> ScratchAnalysis {
        try Task.checkCancellation()
        let lines = text.components(separatedBy: .newlines)
        let mode = ScratchMode.keyword(of: text)
        var result = ScratchAnalysis(mode: mode.isEmpty ? "text" : mode)
        result.source = text
        result.summary = Self.counts(text, lines: lines.count)
        let source = text as NSString
        let sections = ScratchMode.sections(in: text)
        var mathLines: [(line: ScratchMode.Line, inNoteMode: Bool)] = []
        var headers: [(section: ScratchMode.Section, total: String?, hint: String)] = []
        for section in sections {
            try Task.checkCancellation()
            let label = section.mode.capitalized + (section.wholeNote || section.title.isEmpty ? "" : " · \(section.title)")
            let body = section.lines.map { source.substring(with: $0.range) }
            let empty = body.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            switch section.mode {
            case "count":
                let counts = section.wholeNote ? result.summary : Self.counts(body.joined(separator: "\n"), lines: body.count)
                result.results.append(section.wholeNote ? counts : "\(label): " + counts)
                headers.append((section, empty ? nil : counts, "type below to count words, characters and lines"))
            case "sum", "average":
                let numbers = body.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.flatMap(Self.numbers(in:))
                var total: String?
                if !numbers.isEmpty {
                    let value = numbers.reduce(0, +) / (section.mode == "average" ? Double(numbers.count) : 1)
                    result.results.append("\(label): \(Self.format(value)) · \(numbers.count) values")
                    total = "\(Self.format(value)) · \(numbers.count) value\(numbers.count == 1 ? "" : "s")"
                }
                headers.append((section, total, "add numbers on the lines below"))
            case "math":
                result.inlineMath = true
                mathLines += section.lines.map { ($0, section.wholeNote) }
                headers.append((section, nil, "type an expression ending in =, like 12 * 4 ="))
            case "list": headers.append((section, nil, "each line below gets a checkbox"))
            case "code": headers.append((section, nil, "monospaced, indentation kept"))
            default: break
            }
        }
        // Evaluate in document order so variables flow between math sections.
        var variables: [String: Double] = [:]
        var functions: [String: MathFunction] = [:]
        for (lineInfo, inNoteMode) in mathLines.sorted(by: { $0.line.range.location < $1.line.range.location }) {
            let range = lineInfo.range, line = source.substring(with: range)
            try Task.checkCancellation()
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { continue }
            var expression = trimmed
            var variable: String?
            do {
                guard trimmed.utf8.count <= 17_408 else { throw ScratchError.message("Expression too long") }
                if let equals = trimmed.firstIndex(of: "="), !trimmed.hasSuffix("=") {
                    let name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                    expression = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
                    if let (name, function) = try MathFunction.definition(name, expression: expression) {
                        guard functions.count < 64 || functions[name] != nil else { throw ScratchError.message("Too many functions") }
                        functions[name] = function
                        let answer = "Function · " + function.parameters.joined(separator: ", ")
                        result.mathResults.append(ScratchMathResult(range: range, answer: answer))
                        if inNoteMode { result.results.append("Line \(lineInfo.number)  →  \(answer)") }
                        continue
                    }
                    if name.range(of: #"^[a-zA-Z_][a-zA-Z_0-9]*$"#, options: .regularExpression) != nil {
                        variable = name
                    } else { throw ScratchError.message("Invalid definition") }
                } else if trimmed.hasSuffix("=") { expression = String(trimmed.dropLast()) }
                else { continue }
                var explanation: String?
                let value: Double
                if let converted = Self.convert(expression) { value = converted.value }
                else {
                    var parser = MathParser(expression, variables: variables, functions: functions)
                    value = try parser.evaluate(); explanation = parser.explanation
                }
                guard value.isFinite else { throw ScratchError.message("Non-finite result") }
                if let variable { variables[variable] = value }
                let unit = Self.convert(expression)?.unit ?? ""
                let numericAnswer = "\(Self.format(value))\(unit.isEmpty ? "" : " " + unit)"
                let answer = explanation.map { $0 + " = " + numericAnswer } ?? numericAnswer
                if inNoteMode { result.results.append("Line \(lineInfo.number)  →  \(answer)") }
                result.mathResults.append(ScratchMathResult(range: range, answer: answer))
            } catch {
                if inNoteMode { result.results.append("Line \(lineInfo.number)  →  Check expression") }
                result.mathResults.append(ScratchMathResult(range: range, answer: "Check expression"))
            }
        }
        for (section, total, hint) in headers where section.header.length > 0 {
            if let total { result.mathResults.append(ScratchMathResult(range: section.header, answer: total)); continue }
            let filled = section.mode == "math"
                ? result.mathResults.contains { answer in section.lines.contains { $0.range == answer.range } }
                : !section.lines.allSatisfy { source.substring(with: $0.range).trimmingCharacters(in: .whitespaces).isEmpty }
            guard !filled else { continue }
            let ending = section.wholeNote ? "" : " · a blank line ends it"
            result.mathResults.append(ScratchMathResult(range: section.header, answer: hint + ending, isHint: true))
        }
        result.mathResults.sort { $0.range.location < $1.range.location }
        result.checkboxes = NoteCheckbox.find(in: text)
        result.spans = ScratchTextSpan.parse(text)
        try Task.checkCancellation()
        result.prepared = true
        result.cacheCost = text.utf8.count + result.checkboxes.count * 96 + result.spans.count * 64
            + result.mathResults.reduce(0) { $0 + $1.answer.utf8.count + 32 }
        return result
    }

    /// Bound startup work as well as retained memory. Each note is analyzed in
    /// a separate actor call so interactive work can cancel/yield between notes.
    static func counts(_ text: String, lines: Int) -> String {
        "\(text.split(whereSeparator: \.isWhitespace).count) words · \(text.count) characters · \(lines) lines"
    }

    func warmCandidates(_ notes: [ScratchNote]) throws -> [ScratchNote] {
        var cost = 0
        var result: [ScratchNote] = []
        for note in notes where note.deleted == nil {
            try Task.checkCancellation()
            let size = note.content.utf8.count
            guard result.count < ScratchPresentationStore.noteLimit else { break }
            if cost + size > ScratchPresentationStore.byteLimit / 2 { continue }
            cost += size; result.append(note)
        }
        return result
    }

    private static let numberPattern = try! NSRegularExpression(pattern: #"(?<![\d.,])-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?"#)

    /// Numbers for sum/average. Grouped thousands ("1,200") stay one value,
    /// and a hyphen only negates when it is not joining words ("Item-2").
    static func numbers(in line: String) -> [Double] {
        let source = line as NSString
        return numberPattern.matches(in: line, range: NSRange(location: 0, length: source.length)).compactMap { match in
            var token = source.substring(with: match.range)
            if token.hasPrefix("-"), match.range.location > 0,
               let previous = Unicode.Scalar(source.character(at: match.range.location - 1)),
               CharacterSet.alphanumerics.contains(previous) {
                token.removeFirst()
            }
            return Double(token.replacingOccurrences(of: ",", with: ""))
        }
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)).locale(Locale(identifier: "en_US")))
    }

    static func convert(_ expression: String) -> (value: Double, unit: String)? {
        let parts = expression.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 4, parts[2] == "to", let number = Double(parts[0]) else { return nil }
        let units: [String: (String, Double)] = ["m": ("length", 1), "cm": ("length", 0.01), "mm": ("length", 0.001), "km": ("length", 1000), "in": ("length", 0.0254), "ft": ("length", 0.3048), "yd": ("length", 0.9144), "mi": ("length", 1609.344), "g": ("mass", 1), "kg": ("mass", 1000), "lb": ("mass", 453.59237), "oz": ("mass", 28.349523125), "ml": ("volume", 1), "l": ("volume", 1000), "gal": ("volume", 3785.411784), "m/s": ("speed", 1), "km/h": ("speed", 1/3.6), "mph": ("speed", 0.44704), "ft/s": ("speed", 0.3048), "s": ("time", 1), "min": ("time", 60), "h": ("time", 3600)]
        if let from = units[parts[1]], let to = units[parts[3]], from.0 == to.0 { return (number * from.1 / to.1, parts[3]) }
        if parts[1] == "c", parts[3] == "f" { return (number * 9 / 5 + 32, "°F") }
        if parts[1] == "f", parts[3] == "c" { return ((number - 32) * 5 / 9, "°C") }
        return nil
    }

    func ocr(data: Data) throws -> String {
        try Task.checkCancellation()
        guard data.count <= 20 * 1_024 * 1_024 else { throw ScratchError.message("Choose an image smaller than 20 MiB.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: data).perform([request])
        try Task.checkCancellation()
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.isEmpty else { throw ScratchError.message("No text was recognized in this image.") }
        return text
    }
}

/// Numeric functions belong to the note analysis, never global or persisted state.
struct MathFunction: Sendable {
    let parameters: [String]
    let expression: String
    private static let signature = try! NSRegularExpression(pattern: #"^([a-zA-Z_][a-zA-Z_0-9]*)\s*\(([^()]*)\)$"#)
    static func definition(_ signature: String, expression: String) throws -> (String, Self)? {
        let source = signature as NSString
        guard let match = Self.signature.firstMatch(in: signature, range: NSRange(location: 0, length: source.length)) else { return nil }
        let name = source.substring(with: match.range(at: 1))
        let parameters = source.substring(with: match.range(at: 2)).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parameters.count <= 16, Set(parameters).count == parameters.count,
              parameters.allSatisfy({ $0.range(of: #"^[a-zA-Z_][a-zA-Z_0-9]*$"#, options: .regularExpression) != nil }),
              !MathParser.builtins.contains(name.lowercased()),
              !expression.trimmingCharacters(in: .whitespaces).isEmpty, expression.utf8.count <= 16_384 else {
            throw ScratchError.message("Invalid function definition")
        }
        return (name, Self(parameters: parameters, expression: expression))
    }

    private static let substitutionTokens = try! NSRegularExpression(pattern: #"\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+|[a-zA-Z_][a-zA-Z_0-9]*"#)
    func substitution(_ arguments: [Double]) -> String {
        var text = expression
        // Replace whole identifier tokens, so x never alters exp or max.
        let regex = Self.substitutionTokens
        let source = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = parameters.firstIndex(of: source.substring(with: match.range)) else { continue }
            let suffix = source.substring(from: NSMaxRange(match.range)).trimmingCharacters(in: .whitespaces)
            if MathParser.builtins.contains(parameters[index].lowercased()), suffix.hasPrefix("(") { continue }
            var argument = String(arguments[index])
            if argument.hasSuffix(".0") { argument.removeLast(2) }
            text = (text as NSString).replacingCharacters(in: match.range, with: "(" + argument + ")")
        }
        return text
    }
}

/// Shared across nested calls to bound branching as well as recursion.
private final class MathWorkBudget {
    var remaining = 4096
}

/// A bounded arithmetic grammar, rather than executing arbitrary expressions.
struct MathParser {
    private var tokens: [String]
    private var position = 0
    private var depth = 0
    private let variables: [String: Double]
    private let functions: [String: MathFunction]
    private var callDepth = 0
    private var budget = MathWorkBudget()
    private(set) var explanation: String?
    static let builtins: Set<String> = Set(["sqrt", "cbrt", "abs", "ceil", "floor", "round", "trunc", "log", "log10", "log2", "ln", "exp", "sin", "cos", "tan", "asin", "acos", "atan", "arcsin", "arccos", "arctan", "atan2", "sinh", "cosh", "tanh", "asinh", "acosh", "atanh", "rad", "deg", "pow", "hypot", "min", "max"]).union(CourseMath.names)
    private static let groupedNumber = try! NSRegularExpression(pattern: #"(?<![\d.,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d.,])"#)
    private static let tokenPattern = try! NSRegularExpression(pattern: #"\d+(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+|[a-zA-Z_][a-zA-Z_0-9]*|[^\s]"#)
    init(_ expression: String, variables: [String: Double] = [:], functions: [String: MathFunction] = [:]) {
        self.variables = variables
        self.functions = functions
        // Bound normalization/tokenization as well as recursive evaluation.
        guard expression.utf8.count <= 16_384 else { tokens = []; return }
        // Commas separate function arguments. Preserve legacy thousands grouping
        // outside parentheses; inside calls use ungrouped numbers.
        var nesting = 0
        var ungrouped = ""
        var outside = ""
        func flush() {
            // Remove commas only from a complete, valid grouped number.
            let source = outside as NSString
            for match in Self.groupedNumber.matches(in: outside, range: NSRange(location: 0, length: source.length)).reversed() {
                outside = (outside as NSString).replacingCharacters(in: match.range,
                    with: source.substring(with: match.range).replacingOccurrences(of: ",", with: ""))
            }
            ungrouped += outside; outside = ""
        }
        for character in expression {
            if character == "(" { if nesting == 0 { flush() }; nesting += 1 }
            if nesting == 0 { outside.append(character) } else { ungrouped.append(character) }
            if character == ")" { nesting -= 1 }
        }
        flush()
        let normalized = ungrouped.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "**", with: "^").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
        tokens = Self.tokenPattern.matches(in: normalized, range: NSRange(location: 0, length: (normalized as NSString).length)).map { (normalized as NSString).substring(with: $0.range) }
    }
    mutating func evaluate() throws -> Double {
        guard tokens.count <= 512 else { throw ScratchError.message("Expression too long") }
        let result = try sum()
        guard position == tokens.count, result.isFinite else { throw ScratchError.message("Invalid expression") }
        return result
    }
    private var current: String? { position < tokens.count ? tokens[position] : nil }
    private mutating func take(_ value: String) -> Bool {
        guard current == value else { return false }; position += 1; return true
    }
    private mutating func sum() throws -> Double {
        var value = try product()
        while current == "+" || current == "-" {
            let op = current!; position += 1
            let start = position
            let rhs = try product()
            // Colloquial percentages: 100 + 15% = 115.
            let percentage = position > start && tokens[position - 1] == "%"
            let operand = percentage ? value * rhs : rhs
            value = op == "+" ? value + operand : value - operand
        }
        return value
    }
    private mutating func product() throws -> Double {
        var value = try power()
        while let token = current {
            let explicit = ["*", "/", "of"].contains(token) || (token == "x" && variables["x"] == nil && functions["x"] == nil)
            let implicit = token == "(" || variables[token] != nil || functions[token] != nil || Self.builtins.contains(token.lowercased()) || ["pi", "tau", "e"].contains(token.lowercased())
            guard explicit || implicit else { break }
            if explicit { position += 1 }
            let rhs = try power()
            value = token == "/" ? value / rhs : value * rhs
        }
        return value
    }
    private mutating func power() throws -> Double {
        depth += 1; defer { depth -= 1 }
        guard depth < 64 else { throw ScratchError.message("Expression too deep") }
        var value = try atom()
        if take("^") { value = pow(value, try power()) }
        if take("%") { value /= 100 }
        return value
    }
    private mutating func atom() throws -> Double {
        if take("+") { return try power() }
        if take("-") { return -(try power()) }
        if take("(") { let value = try sum(); guard take(")") else { throw ScratchError.message("Missing parenthesis") }; return value }
        guard let token = current else { throw ScratchError.message("Missing number") }
        budget.remaining -= 1
        guard budget.remaining >= 0 else { throw ScratchError.message("Calculation too complex") }
        let start = position
        position += 1
        if let number = Double(token) { return number }
        // A call takes priority over a same-named variable. Bare identifiers
        // still resolve to user variables before built-in constants.
        if (functions[token] != nil || Self.builtins.contains(token.lowercased()) || variables[token] == nil), take("(") {
            var arguments: [Double] = []
            if !take(")") {
                repeat { arguments.append(try sum()) } while take(",")
                guard take(")") else { throw ScratchError.message("Missing parenthesis") }
            }
            if let function = functions[token] {
                guard arguments.count == function.parameters.count, arguments.allSatisfy(\.isFinite), callDepth < 16 else {
                    throw ScratchError.message("Invalid function call")
                }
                var local = variables
                for (parameter, value) in zip(function.parameters, arguments) { local[parameter] = value }
                var parser = MathParser(function.expression, variables: local, functions: functions)
                parser.callDepth = callDepth + 1; parser.budget = budget
                let value = try parser.evaluate()
                if start == 0, position == tokens.count {
                    explanation = function.substitution(arguments)
                }
                return value
            }
            return try Self.call(token.lowercased(), arguments: arguments)
        }
        if let value = variables[token] { return value }
        switch token.lowercased() {
        case "pi": return .pi
        case "tau": return 2 * .pi
        case "e": return exp(1)
        default: break
        }
        throw ScratchError.message("Unknown variable")
    }

    /// Only explicitly supported numeric functions are callable. Every argument
    /// and result must be finite, including nested domain/overflow errors.
    private static func call(_ name: String, arguments: [Double]) throws -> Double {
        guard arguments.allSatisfy(\.isFinite) else { throw ScratchError.message("Invalid argument") }
        func require(_ count: Int) throws {
            guard arguments.count == count else { throw ScratchError.message("Wrong number of arguments") }
        }
        let value: Double
        if CourseMath.names.contains(name) {
            value = try CourseMath.evaluate(name, arguments)
        } else if ["min", "max"].contains(name) {
            guard !arguments.isEmpty else { throw ScratchError.message("Missing argument") }
            value = name == "min" ? arguments.min()! : arguments.max()!
        } else if ["pow", "atan2", "hypot", "log"].contains(name), arguments.count == 2 {
            let a = arguments[0], b = arguments[1]
            switch name {
            case "pow": value = pow(a, b)
            case "atan2": value = atan2(a, b) // y, x; radians
            case "hypot": value = hypot(a, b)
            default:
                guard a > 0, b > 0, b != 1 else { throw ScratchError.message("Invalid logarithm") }
                value = log(a) / log(b)
            }
        } else {
            try require(1)
            let a = arguments[0]
            switch name {
            case "sqrt": value = sqrt(a)
            case "cbrt": value = cbrt(a)
            case "abs": value = abs(a)
            case "ceil": value = ceil(a)
            case "floor": value = floor(a)
            case "round": value = a.rounded()
            case "trunc": value = a.rounded(.towardZero)
            case "log", "log10": value = log10(a)
            case "log2": value = log2(a)
            case "ln": value = log(a)
            case "exp": value = exp(a)
            case "sin": value = sin(a)
            case "cos": value = cos(a)
            case "tan": value = tan(a)
            case "asin", "arcsin": value = asin(a)
            case "acos", "arccos": value = acos(a)
            case "atan", "arctan": value = atan(a)
            case "sinh": value = sinh(a)
            case "cosh": value = cosh(a)
            case "tanh": value = tanh(a)
            case "asinh": value = asinh(a)
            case "acosh": value = acosh(a)
            case "atanh": value = atanh(a)
            case "rad": value = a / 180 * .pi
            case "deg": value = a / .pi * 180
            default: throw ScratchError.message("Unknown function")
            }
        }
        guard value.isFinite else { throw ScratchError.message("Non-finite result") }
        return value
    }

}

struct ScratchTimerCommand: Equatable, Sendable {
    var duration: TimeInterval? // nil means stopwatch
    var label: String
    static func parse(_ line: String) -> ScratchTimerCommand? {
        guard line.lowercased().hasPrefix("timer") else { return nil }
        var body = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        var label = "Scratchpad"
        if let range = body.range(of: #":(?=\s|[^0-9]|$)"#, options: .regularExpression) {
            label = String(body[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            body = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if label.isEmpty { label = "Scratchpad" }
        }
        if body.isEmpty { return Self(duration: nil, label: label) }
        if body.lowercased() == "pomo" { return Self(duration: 25 * 60, label: "\(label) · Focus") }
        let parts = body.split(separator: ":")
        let duration: Double?
        if parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]), seconds < 60 {
            duration = minutes * 60 + seconds
        } else { duration = Double(body).map { $0 * 60 } }
        guard let duration, duration > 0, duration <= 7 * 86_400 else { return nil }
        return Self(duration: duration, label: label)
    }
}


/// UI-side projection of actor-produced results. No parsing or hashing of note
/// bodies occurs here. Derived state is intentionally not written to disk.
struct ScratchPresentationStore {
    static let noteLimit = 128
    static let byteLimit = 16 * 1_024 * 1_024
    private var entries: [String: ScratchAnalysis] = [:]
    private var order: [String] = []
    private(set) var cost = 0
    var count: Int { entries.count }

    mutating func result(for id: String, text: String) -> ScratchAnalysis? {
        guard let result = entries[id], result.source == text else { return nil }
        order.removeAll { $0 == id }; order.append(id)
        return result
    }

    mutating func insert(_ result: ScratchAnalysis, for id: String) {
        if let previous = entries.removeValue(forKey: id) { cost -= previous.cacheCost }
        order.removeAll { $0 == id }
        guard result.prepared, result.cacheCost <= Self.byteLimit else { return }
        entries[id] = result; order.append(id); cost += result.cacheCost
        while entries.count > Self.noteLimit || cost > Self.byteLimit {
            let oldest = order.removeFirst()
            if let evicted = entries.removeValue(forKey: oldest) { cost -= evicted.cacheCost }
        }
    }
}
