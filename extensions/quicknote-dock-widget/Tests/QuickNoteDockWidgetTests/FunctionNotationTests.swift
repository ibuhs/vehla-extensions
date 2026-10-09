import Foundation
import Testing
@testable import QuickNoteDockWidget

@Suite struct FunctionNotationTests {
    @Test func textbookFunctionShowsSubstitutionAndOutputs() async throws {
        let text = "math\nf(x) = 5x - 2\n" + (1...6).map { "f(\($0)) =" }.joined(separator: "\n")
        let result = try await ScratchTools().analyze(text)
        #expect(result.mathResults.map(\.answer) == ["Function · x", "5(1) - 2 = 3", "5(2) - 2 = 8", "5(3) - 2 = 13", "5(4) - 2 = 18", "5(5) - 2 = 23", "5(6) - 2 = 28"])
        #expect(result.source == text)
        let updated = try await ScratchTools().analyze(text.replacingOccurrences(of: "5x - 2", with: "x^2"))
        #expect(updated.mathResults.last?.answer == "(6)^2 = 36")
    }

    @Test func localParametersNestedCallsAndRedefinitions() async throws {
        let result = try await ScratchTools().analyze("math\nx = 99\na = 2\nf(x) = a*x\ny = f(3)\nx =\ng(x) = f(x)^2\ng(3) =\n\ntext\nAnother section\nmath\na = 4\nf(3) =\nf(x) = x+1\nf(3) =\narea(w,h) = w*h\narea(3,4) =\nf(1) + area(2,3) =")
        #expect(result.mathResults.map(\.answer) == ["99", "2", "Function · x", "a*(3) = 6", "99", "Function · x", "f((3))^2 = 36", "4", "a*(3) = 12", "Function · x", "(3)+1 = 4", "Function · w, h", "(3)*(4) = 12", "8"])
    }

    @Test func implicitMultiplicationPreservesArithmeticAndScientificFunctions() throws {
        let f = MathFunction(parameters: ["x"], expression: "5x-2")
        for (text, answer) in [("2pi", 2 * Double.pi), ("2sin(pi/2)", 2.0), ("3(2+1)", 9.0),
                               ("2 x 3", 6.0), ("2^3(1+1)", 16.0), ("6/2(1+2)", 9.0),
                               ("2f(3)", 26.0), ("x(x+1)", 12.0), ("(2+1)(3+1)", 12.0)] {
            var parser = MathParser(text, variables: text == "x(x+1)" ? ["x": 3] : [:], functions: ["f": f])
            #expect(abs(try parser.evaluate() - answer) < 1e-9, "\(text)")
        }
    }

    @Test func functionNamedXDoesNotBecomeMultiplicationAlias() throws {
        var parser = MathParser("2x(3)", functions: ["x": MathFunction(parameters: ["t"], expression: "t+1")])
        #expect(try parser.evaluate() == 8)
    }

    @Test func invalidDefinitionsAndCallsStayBounded() async throws {
        let text = "math\nf(x,x) = x\nsin(x) = x\nf() = 2\nf(x) =\nf(x) = f(x)\nf(1) =\ng(x) = g(x)+g(x)\ng(1) =\nh(x) = sqrt(x)\nh(-1) =\nh(1,2) =\nunknown(1) =\ncos(0) ="
        let result = try await ScratchTools().analyze(text)
        #expect(result.mathResults.filter { $0.answer == "Check expression" }.count == 9)
        #expect(result.mathResults.last?.answer == "1", "A failed function must not prevent later results")
        var parser = MathParser("f(1)", functions: ["f": MathFunction(parameters: ["x"], expression: "f(x)+f(x)")])
        #expect(throws: (any Error).self) { try parser.evaluate() }
    }

    @Test func substitutionsDoNotAlterIdentifiersOrScientificNotation() async throws {
        let result = try await ScratchTools().analyze("math\nf(e) = 1e-3 + e\nf(2) =\ng(x) = exp(x) + max(x, 1)\ng(-2) =\nf(-3) =")
        #expect(result.mathResults[1].answer == "1e-3 + (2) = 2.001")
        #expect(result.mathResults[3].answer == "exp((-2)) + max((-2), 1) = 1.135335")
        #expect(result.mathResults[4].answer == "1e-3 + (-3) = -2.999")
    }
}
