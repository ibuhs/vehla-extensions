import Foundation

/// The path a breathing exercise is traced along, in a unit square (y grows downward).
/// A point travels once around it per breath cycle, so box breathing walks the four sides of a square.
public enum BreathTrack: Sendable, Equatable {
    case roundedSquare, circle

    public static func forPattern(_ pattern: BreathPattern) -> BreathTrack { pattern.id == "box" ? .roundedSquare : .circle }

    public static let cornerRadius = 0.18

    /// Position at `t` (0...1, wraps). Both tracks start on the left and head up, travelling clockwise.
    /// The rounded square starts at the middle of the bottom-left corner so each equal phase covers one
    /// quarter of the loop, ending on the next corner.
    public func point(at t: Double) -> (x: Double, y: Double) {
        let t = t - floor(t)
        switch self {
        case .circle:
            let angle = Double.pi + 2 * Double.pi * t
            return (0.5 + 0.5 * cos(angle), 0.5 + 0.5 * sin(angle))
        case .roundedSquare:
            return Self.roundedSquarePoint(t)
        }
    }

    private static func roundedSquarePoint(_ t: Double) -> (x: Double, y: Double) {
        let r = cornerRadius, straight = 1 - 2 * r, quarter = Double.pi * r / 2
        let total = 4 * straight + 4 * quarter
        var s = t * total

        // Corner arcs sweep clockwise on screen; phi is measured with y pointing down.
        func arc(_ cx: Double, _ cy: Double, from: Double, length: Double) -> (x: Double, y: Double)? {
            guard s <= length else { s -= length; return nil }
            let phi = from + (s / r)
            return (cx + r * cos(phi), cy + r * sin(phi))
        }
        func line(_ x0: Double, _ y0: Double, _ dx: Double, _ dy: Double) -> (x: Double, y: Double)? {
            guard s <= straight else { s -= straight; return nil }
            return (x0 + dx * s, y0 + dy * s)
        }
        // Start 45° into the bottom-left corner.
        if let p = arc(r, 1 - r, from: 3 * Double.pi / 4, length: quarter / 2) { return p }
        if let p = line(0, 1 - r, 0, -1) { return p }
        if let p = arc(r, r, from: Double.pi, length: quarter) { return p }
        if let p = line(r, 0, 1, 0) { return p }
        if let p = arc(1 - r, r, from: 3 * Double.pi / 2, length: quarter) { return p }
        if let p = line(1, r, 0, 1) { return p }
        if let p = arc(1 - r, 1 - r, from: 0, length: quarter) { return p }
        if let p = line(1 - r, 1, -1, 0) { return p }
        // The first half of the bottom-left arc, completing the loop.
        let phi = Double.pi / 2 + s / r
        return (r + r * cos(phi), 1 - r + r * sin(phi))
    }

    /// Points along the track between two positions, for drawing a stroke.
    public func samples(from t0: Double, to t1: Double, step: Double = 0.004) -> [(x: Double, y: Double)] {
        guard t1 > t0 else { return [point(at: t0)] }
        let count = max(1, Int(((t1 - t0) / step).rounded(.up)))
        return (0...count).map { point(at: t0 + (t1 - t0) * Double($0) / Double(count)) }
    }
}
