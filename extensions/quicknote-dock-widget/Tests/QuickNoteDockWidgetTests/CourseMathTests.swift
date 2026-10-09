import Foundation
import Testing
@testable import QuickNoteDockWidget

@Suite struct CourseMathTests {
    static let cases: [ScientificMathCase] = [
        .init("sum(350,125,30,150,40,40)", 735), .init("mean(2,4,4,4,5,5,7,9)", 5),
        .init("average(2,4)", 3), .init("median(1,7,3,5)", 4), .init("median(1,7,3)", 3),
        .init("mode(2,2,1,1,3)", 1), .init("variance(1,2,3)", 1), .init("stdev(1,2,3)", 1),
        .init("stdevp(2,4,4,4,5,5,7,9)", 2), .init("variancep(2,4,4,4,5,5,7,9)", 4),
        .init("percentile(.75,10,20,30,40)", 32.5), .init("percentile(1,10,20)", 20),
        .init("percentrank(20,10,20,30,40)", 0.5), .init("PMT(4.2%/12,120,2800)", -28.6155450685489),
        .init("FV(.95%/12,60,-210)", 12898.8176139077), .init("pmt(0,10,100)", -10),
        .init("fv(0,10,-10,-100)", 200), .init("pv(0,10,-10,200)", -100),
        .init("nper(0,-10,100)", 10), .init("nper(.01,pmt(.01,12,100),100)", 12),
        .init("pv(.01,12,pmt(.01,12,100))", 100),
        .init("fv(.01,12,pmt(.01,12,100),100)", 0),
        .init("pmt(.01,12,100,0,1)*(1.01)-pmt(.01,12,100)", 0),
        .init("compound(100,12%,1,12)", 112.682503013197), .init("growth(100,5%,2)", 110.25),
        .init("percentchange(80,100)", 0.25), .init("slope(0,32000,1,33600)", 1600),
        .init("vertexx(-2,8)", 2), .init("vertexy(-2,8,3)", 11),
        .init("discriminant(1,-5,6)", 1), .init("quadraticroot(1,-5,6,-1)", 2),
        .init("quadraticroot(1,-5,6,1)", 3), .init("quadraticroot(1,0,0,1)", 0),
        .init("systemx(2,1,8,1,-1,1)", 3), .init("systemy(2,1,8,1,-1,1)", 2),
        .init("regslope(1,3,2,5,3,7)", 2), .init("regintercept(1,3,2,5,3,7)", 1),
        .init("correlation(1,3,2,2,3,1)", -1), .init("rsquared(1,3,2,5,3,7)", 1),
        .init("expfit_a(0,2,1,6,2,18)", 2), .init("expfit_b(0,2,1,6,2,18)", 3),
        .init("quadfit_a(-1,6,0,3,1,4,2,9)", 2), .init("quadfit_b(-1,6,0,3,1,4,2,9)", -1),
        .init("quadfit_c(-1,6,0,3,1,4,2,9)", 3), .init("probability(72,200)", 0.36),
        .init("margin(100)", 0.1), .init("cilower(72,200)", 0.36-1/sqrt(200)),
        .init("ciupper(72,200)", 0.36+1/sqrt(200)), .init("cisample(3%)", 1112),
        .init("gcd(12,18)", 6), .init("lcm(4,3)", 12), .init("gcd(0,0)", 0),
        .init("eq(2,2)+lt(1,2)+le(1,1)+gt(3,1)+ge(3,3)", 5),
        .init("and(1,or(0,1),not(0))", 1)
    ]
    @Test(arguments: cases) func courseCalculations(_ test: ScientificMathCase) throws {
        var parser = MathParser(test.expression)
        #expect(abs(try parser.evaluate()-test.answer) < 1e-7, "\(test.expression)")
    }
    @Test(arguments: ["pmt(-1,12,100)", "pmt(0,0,100)", "fv(.01,12,1,2,3)", "nper(0,0,100)",
                      "compound(100,1,10,0)", "compound(100,1,10,1.5)", "growth(100,-1,2)",
                      "percentchange(0,1)", "slope(1,2,1,3)", "vertexx(0,1)",
                      "quadraticroot(1,0,1,1)", "quadraticroot(0,1,2,1)", "quadraticroot(1,0,0,0)",
                      "systemx(1,2,3,2,4,6)", "systemy(0,0,1,1,1,2)", "mean()", "stdev(1)",
                      "mode(1,2,3)", "percentile(2,1,2)", "variance()", "regslope(1,2,1,3)",
                      "regslope(1,2,3)", "correlation(1,2,2,2)", "expfit_a(0,-1,1,2)",
                      "quadfit_a(1,2,1,3,2,4)", "quadfit_c(1,2,2,3)", "probability(3,2)",
                      "probability(.5,2)", "margin(0)", "cisample(0)", "gcd(.5,2)", "and(2,1)", "not(2)"])
    func rejectsInvalidCourseInputs(_ expression: String) {
        var parser = MathParser(expression)
        #expect(throws: (any Error).self) { try parser.evaluate() }
    }
    @Test func everyExampleProducesRealResultsWithoutErrors() async throws {
        let tools = ScratchTools()
        for example in CourseMathExamples.all {
            let result = try await tools.analyze(example.content)
            #expect(result.inlineMath && !result.mathResults.isEmpty)
            #expect(!result.mathResults.contains { $0.answer == "Check expression" }, "\(example.title)")
        }
        let units = try await tools.analyze("math\n140 m/s to km/h =\n25 mph to ft/s =")
        #expect(units.mathResults.map(\.answer) == ["504 km/h", "36.666667 ft/s"])
    }
    @Test func statisticsAndRootsRetainPrecision() throws {
        var parser = MathParser("stdev(1000000000001,1000000000002,1000000000003)")
        #expect(try parser.evaluate() == 1)
        parser = MathParser("quadraticroot(1,100000000,1,1)")
        #expect(abs(try parser.evaluate() + 1e-8) < 1e-15)
        parser = MathParser("quadfit_a(999999,6,1000000,3,1000001,4,1000002,9)")
        #expect(abs(try parser.evaluate()-2) < 1e-9)
    }
}
