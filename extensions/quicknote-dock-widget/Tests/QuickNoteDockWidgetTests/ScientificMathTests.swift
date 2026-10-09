import Foundation
import Testing
@testable import QuickNoteDockWidget

struct ScientificMathCase: Sendable {
    let expression: String
    let answer: Double
    init(_ expression: String, _ answer: Double) { self.expression = expression; self.answer = answer }
}

@Suite struct ScientificMathTests {
    static let examples: [ScientificMathCase] = [
        ScientificMathCase("sin(pi / 2)", 1), .init("cos(π)", -1), .init("tan(pi / 4)", 1),
        .init("sin(rad(30))", 0.5), .init("deg(asin(0.5))", 30), .init("acos(0)", .pi / 2),
        .init("atan(1)", .pi / 4), .init("atan2(1, -1)", 3 * .pi / 4),
        .init("arcsin(1) + arccos(1) + arctan(0)", .pi / 2),
        .init("sinh(0) + cosh(0) + tanh(0)", 1), .init("asinh(sinh(2))", 2),
        .init("acosh(cosh(2))", 2), .init("atanh(tanh(0.5))", 0.5),
        .init("ln(e)", 1), .init("exp(ln(5))", 5), .init("log(100)", 2),
        .init("log10(1000) + log2(8)", 6), .init("log(81, 3)", 4),
        .init("sqrt(pow(3, 2) + pow(4, 2))", 5), .init("hypot(3, 4)", 5),
        .init("cbrt(-27)", -3), .init("min(3, -2, pow(2, 3))", -2),
        .init("max(1200, 1500)", 1500), .init("max(7)", 7),
        .init("round(-2.5) + trunc(2.9)", -1), .init("abs(-3) + ceil(1.2) + floor(1.8)", 6),
        .init("SIN(PI / 2)", 1), .init("tau / pi", 2), .init("1e-3 + .5", 0.501),
        .init("1,200 + 300", 1500), .init("1,234,567 + 1", 1234568),
        .init("−2^2", -4), .init("2^3^2", 512), .init("50% of 200", 100),
        .init("100 + 15%", 115), .init("pow(2, -3)", 0.125)
    ]

    @Test(arguments: examples)
    func evaluatesScientificExpressions(_ test: ScientificMathCase) throws {
        var parser = MathParser(test.expression)
        #expect(abs(try parser.evaluate() - test.answer) < 1e-9, "\(test.expression)")
    }

    @Test(arguments: ["sin()", "cos(1, 2)", "pow(2)", "hypot(1, 2, 3)", "atan2(1)",
                      "min()", "max()", "log(8, 1)", "log(8, -2)", "ln(0)", "log(-1)",
                      "sqrt(-1)", "asin(2)", "acos(-2)", "acosh(0)", "atanh(1)",
                      "exp(1000)", "pow(-2, 0.5)", "atan(1 / 0)", "sin(x)",
                      "unknown(1)", "sin(pi", "pow(2,)", "max(,2)", "1,2", "sin(1) junk"])
    func rejectsInvalidExpressions(_ expression: String) {
        var parser = MathParser(expression)
        #expect(throws: (any Error).self) { try parser.evaluate() }
    }

    @Test func functionsAndVariablesFlowAcrossMathSections() async throws {
        let text = "math: Angles\nx = pi / 4\nsin(x)^2 + cos(x)^2 =\n\ntext\nInterlude\nmath\nx = rad(30)\nsin(x) =\nlog(pow(3, 4), 3) =\nsqrt(-1) =\ncos(0) ="
        let analysis = try await ScratchTools().analyze(text)
        #expect(analysis.inlineMath)
        #expect(analysis.mathResults.map(\.answer) == ["0.785398", "1", "0.523599", "0.5", "4", "Check expression", "1"])
        #expect(analysis.source == text, "Answers must never be inserted into note text")
        for result in analysis.mathResults {
            #expect((text as NSString).substring(with: result.range).contains("="))
        }
        let updated = try await ScratchTools().analyze(text.replacingOccurrences(of: "rad(30)", with: "rad(90)"))
        #expect(updated.mathResults[3].answer == "1")
    }

    @Test func parsingRemainsBoundedAndVariablesCanUseFunctionNames() throws {
        var parser = MathParser(String(repeating: "sin(", count: 70) + "0" + String(repeating: ")", count: 70))
        #expect(throws: (any Error).self) { try parser.evaluate() }
        parser = MathParser(Array(repeating: "1", count: 300).joined(separator: "+"))
        #expect(throws: (any Error).self) { try parser.evaluate() }
        parser = MathParser(String(repeating: "1", count: 16_385))
        #expect(throws: (any Error).self) { try parser.evaluate() }
        parser = MathParser("sin + sin(x)", variables: ["sin": 2, "x": .pi / 2])
        #expect(try parser.evaluate() == 3)
    }
}
