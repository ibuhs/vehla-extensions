import Foundation

/// Geometry of the drinking glass in a 76 x 92 box, shared by the physics and the renderer.
/// The rim and base are ellipses seen from slightly above. Wall and base thickness are scaled down from a
/// full-size widget to suit the Notch's small tab area.
public enum CupGeometry {
    public static let width = 76.0
    public static let height = 92.0
    public static let cx = 38.0
    public static let topY = 12.0
    public static let bottomY = 80.0
    public static let topHalf = 28.0
    public static let bottomHalf = 20.0
    public static let rimRY = 5.5
    public static let bottomRY = 4.5
    /// Glass wall thickness.
    public static let wall = 3.0
    /// Thickness of the solid glass punt at the base.
    public static let base = 11.0
    /// The table the glass stands on, where spilled water lands.
    public static let groundY = bottomY + bottomRY + 2.0
    public static let kappa = 4.0 / 3.0

    /// Outer half-width of the glass at height y.
    public static func half(_ y: Double) -> Double {
        let t = min(1, max(0, (y - topY) / (bottomY - topY)))
        return topHalf + (bottomHalf - topHalf) * t
    }

    public static var cavityBottomY: Double { bottomY - base }
    public static func cavityHalf(_ y: Double) -> Double { half(y) - wall }
    public static func rimRY(forHalf h: Double) -> Double { rimRY * h / topHalf }

    /// Centre-line height of the water surface for a fill `level` (0...1). At 1 the surface meets the rim.
    public static func waterlineY(_ level: Double) -> Double {
        let top = topY + 0.5, bottom = cavityBottomY
        return bottom - (bottom - top) * min(1, max(0, level))
    }
}
