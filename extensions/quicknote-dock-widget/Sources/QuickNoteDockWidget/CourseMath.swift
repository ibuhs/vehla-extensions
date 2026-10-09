import Foundation

/// Course helpers are numeric operations within MathParser's existing actor pipeline.
/// No spreadsheet runtime, I/O, UI state, or external evaluator is involved.
enum CourseMath {
    static let names: Set<String> = ["sum", "mean", "average", "median", "mode", "stdev", "stdevp", "variance", "variancep", "percentile", "percentrank", "pmt", "fv", "pv", "nper", "compound", "growth", "percentchange", "slope", "vertexx", "vertexy", "discriminant", "quadraticroot", "systemx", "systemy", "regslope", "regintercept", "correlation", "rsquared", "expfit_a", "expfit_b", "quadfit_a", "quadfit_b", "quadfit_c", "probability", "margin", "cilower", "ciupper", "cisample", "gcd", "lcm", "eq", "lt", "le", "gt", "ge", "and", "or", "not"]

    static func evaluate(_ name: String, _ args: [Double]) throws -> Double {
        guard !args.isEmpty, args.allSatisfy(\.isFinite) else { throw ScratchError.message("Invalid arguments") }
        func count(_ n: Int) throws { guard args.count == n else { throw ScratchError.message("Wrong number of arguments") } }
        func valid(_ condition: Bool) throws { guard condition else { throw ScratchError.message("Invalid domain") } }
        func integer(_ x: Double) -> Bool { x.rounded() == x && abs(x) <= 1e12 }
        let a = args[0]
        switch name {
        case "sum": return args.reduce(0, +)
        case "mean", "average": return args.reduce(0) { $0 + $1 / Double(args.count) }
        case "median":
            let sorted = args.sorted(), n = sorted.count
            return n % 2 == 1 ? sorted[n/2] : sorted[n/2-1]/2 + sorted[n/2]/2
        case "mode":
            let counts = Dictionary(args.map { ($0, 1) }, uniquingKeysWith: +)
            let largest = counts.values.max()!
            try valid(largest > 1)
            return counts.filter { $0.value == largest }.keys.min()!
        case "stdev", "stdevp", "variance", "variancep":
            let population = name.hasSuffix("p")
            try valid(population || args.count > 1)
            var mean = 0.0, squares = 0.0
            for (i, x) in args.enumerated() {
                let delta = x - mean; mean += delta / Double(i+1); squares += delta * (x-mean)
            }
            let variance = max(0, squares / Double(args.count - (population ? 0 : 1)))
            return name.hasPrefix("stdev") ? sqrt(variance) : variance
        case "percentile":
            try valid(args.count >= 2 && (0...1).contains(a))
            let data = args.dropFirst().sorted(), rank = a * Double(data.count-1), low = Int(floor(rank)), high = Int(ceil(rank))
            return data[low] * (1 - (rank-Double(low))) + data[high] * (rank-Double(low))
        case "percentrank":
            try valid(args.count >= 2)
            return Double(args.dropFirst().filter { $0 <= a }.count) / Double(args.count-1)
        case "pmt", "fv", "pv", "nper":
            try valid((3...5).contains(args.count) && a > -1)
            let b = args[1], c = args[2], d = args.count > 3 ? args[3] : 0, type = args.count > 4 ? args[4] : 0
            try valid(type == 0 || type == 1)
            if name == "nper" {
                let periods: Double
                if a == 0 { try valid(b != 0); periods = -(c+d)/b }
                else {
                    let annuity = b * (1 + a*type) / a
                    let ratio = (annuity-d)/(annuity+c)
                    try valid(ratio > 0); periods = log(ratio)/log1p(a)
                }
                try valid(periods >= 0); return periods
            }
            try valid(b >= 0 && (name != "pmt" || b > 0))
            let growth = exp(b * log1p(a)), annuity = (a == 0 ? b : expm1(b * log1p(a)) / a) * (1 + a*type)
            switch name {
            case "pmt": return -(c*growth+d)/annuity
            case "fv": return -(d*growth+c*annuity)
            default: return -(d+c*annuity)/growth
            }
        case "compound":
            try valid(args.count == 3 || args.count == 4)
            let periods = args.count == 4 ? args[3] : 12
            try valid(periods > 0 && integer(periods) && args[2] >= 0 && args[1]/periods > -1)
            return a * exp(periods * args[2] * log1p(args[1]/periods))
        case "growth":
            try count(3); try valid(args[1] > -1)
            return a * exp(args[2] * log1p(args[1]))
        case "percentchange": try count(2); try valid(a != 0); return (args[1]-a)/a
        case "slope": try count(4); try valid(args[2] != a); return (args[3]-args[1])/(args[2]-a)
        case "vertexx": try count(2); try valid(a != 0); return -args[1]/(2*a)
        case "vertexy":
            try count(3); try valid(a != 0)
            let x = -args[1]/(2*a); return (a*x+args[1])*x+args[2]
        case "discriminant": try count(3); return args[1]*args[1]-4*a*args[2]
        case "quadraticroot":
            try count(4); try valid(a != 0 && (args[3] == -1 || args[3] == 1))
            let scale = max(abs(a), abs(args[1]), abs(args[2])), aa = a/scale, b = args[1]/scale, c = args[2]/scale
            let disc = b*b-4*aa*c; try valid(disc >= 0)
            let q = -0.5 * (b + (b >= 0 ? sqrt(disc) : -sqrt(disc)))
            let roots = q == 0 ? [0.0, 0.0] : [q/aa, c/q].sorted()
            return args[3] == -1 ? roots[0] : roots[1]
        case "systemx", "systemy":
            try count(6)
            let s1 = max(abs(a), abs(args[1])), s2 = max(abs(args[3]), abs(args[4]))
            try valid(s1 > 0 && s2 > 0)
            let aa = a/s1, b = args[1]/s1, c = args[2]/s1, d = args[3]/s2, e = args[4]/s2, f = args[5]/s2
            let determinant = aa*e-b*d; try valid(abs(determinant) > 1e-12)
            return name == "systemx" ? (c*e-b*f)/determinant : (aa*f-c*d)/determinant
        case "regslope", "regintercept", "correlation", "rsquared", "expfit_a", "expfit_b", "quadfit_a", "quadfit_b", "quadfit_c":
            try valid(args.count >= 4 && args.count % 2 == 0)
            var xs: [Double] = [], ys: [Double] = []
            for i in stride(from: 0, to: args.count, by: 2) { xs.append(args[i]); ys.append(args[i+1]) }
            if name.hasPrefix("quadfit") {
                let coefficients = try quadraticFit(xs, ys)
                return coefficients[name == "quadfit_a" ? 0 : name == "quadfit_b" ? 1 : 2]
            }
            if name.hasPrefix("expfit") { try valid(ys.allSatisfy { $0 > 0 }); ys = ys.map { log($0) } }
            let n = Double(xs.count), mx = xs.reduce(0) { $0+$1/n }, my = ys.reduce(0) { $0+$1/n }
            var xx = 0.0, yy = 0.0, xy = 0.0
            for i in xs.indices { let dx = xs[i]-mx, dy = ys[i]-my; xx += dx*dx; yy += dy*dy; xy += dx*dy }
            try valid(xx > 0)
            let slope = xy/xx, intercept = my-slope*mx
            switch name {
            case "regslope": return slope
            case "regintercept": return intercept
            case "expfit_a": return exp(intercept)
            case "expfit_b": return exp(slope)
            default:
                try valid(yy > 0)
                let correlation = max(-1, min(1, (xy/sqrt(xx))/sqrt(yy)))
                return name == "rsquared" ? correlation*correlation : correlation
            }
        case "probability", "cilower", "ciupper":
            try count(2); let n = args[1]
            try valid(integer(a) && integer(n) && n > 0 && a >= 0 && a <= n)
            let p = a/n
            return name == "probability" ? p : p + (name == "cilower" ? -1 : 1)/sqrt(n)
        case "margin": try count(1); try valid(integer(a) && a > 0); return 1/sqrt(a)
        case "cisample": try count(1); try valid(a > 0 && a <= 1); return ceil(1/(a*a))
        case "gcd", "lcm":
            try count(2); try valid(integer(a) && integer(args[1]))
            var x = Int64(abs(a)), y = Int64(abs(args[1]))
            while y != 0 { let r = x % y; x = y; y = r }
            return name == "gcd" ? Double(x) : x == 0 ? 0 : (abs(a)/Double(x))*abs(args[1])
        case "eq", "lt", "le", "gt", "ge":
            try count(2); let b = args[1]
            switch name {
            case "eq": return a == b ? 1 : 0
            case "lt": return a < b ? 1 : 0
            case "le": return a <= b ? 1 : 0
            case "gt": return a > b ? 1 : 0
            default: return a >= b ? 1 : 0
            }
        case "and", "or":
            try valid(args.allSatisfy { $0 == 0 || $0 == 1 })
            return (name == "and" ? args.allSatisfy { $0 == 1 } : args.contains(1)) ? 1 : 0
        case "not": try count(1); try valid(a == 0 || a == 1); return 1-a
        default: throw ScratchError.message("Unknown function")
        }
    }

    /// Center and scale x before solving the small least-squares system.
    /// Reject degenerate input rather than returning misleading coefficients.
    private static func quadraticFit(_ xs: [Double], _ ys: [Double]) throws -> [Double] {
        guard xs.count >= 3 else { throw ScratchError.message("Need three points") }
        let mean = xs.reduce(0) { $0 + $1/Double(xs.count) }, scale = xs.map { abs($0-mean) }.max()!
        guard scale > 0 else { throw ScratchError.message("Degenerate data") }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 4), count: 3)
        for i in xs.indices {
            let t = (xs[i]-mean)/scale, row = [t*t, t, 1.0]
            for r in 0..<3 { for c in 0..<3 { matrix[r][c] += row[r]*row[c] }; matrix[r][3] += row[r]*ys[i] }
        }
        for column in 0..<3 {
            let pivot = (column..<3).max { abs(matrix[$0][column]) < abs(matrix[$1][column]) }!
            matrix.swapAt(column, pivot)
            guard abs(matrix[column][column]) > 1e-12 * Double(xs.count) else { throw ScratchError.message("Degenerate data") }
            let divisor = matrix[column][column]
            for c in column..<4 { matrix[column][c] /= divisor }
            for r in 0..<3 where r != column {
                let factor = matrix[r][column]
                for c in column..<4 { matrix[r][c] -= factor*matrix[column][c] }
            }
        }
        let a = matrix[0][3]/scale/scale, b = matrix[1][3]/scale-2*a*mean, c = matrix[2][3]-matrix[1][3]*mean/scale+a*mean*mean
        return [a, b, c]
    }
}
