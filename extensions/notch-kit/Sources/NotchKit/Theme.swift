import SwiftUI

/// Design tokens. The Notch is always dark, so everything is tuned for a black background.
public enum NK {
    public enum Metric {
        /// Horizontal inset of tab content.
        public static let inset: CGFloat = 14
        /// Clearance from the panel's rounded corners, so headers and corner buttons aren't clipped.
        public static let cornerClearance: CGFloat = 26
        public static let topClearance: CGFloat = 12
        public static let bottomClearance: CGFloat = 12
        public static let spacing: CGFloat = 8
        public static let radius: CGFloat = 10
        public static let controlHeight: CGFloat = 26
        public static let hairline: CGFloat = 1
    }

    public enum Palette {
        public static let primary = Color.white
        public static let secondary = Color.white.opacity(0.6)
        public static let tertiary = Color.white.opacity(0.38)
        public static let surface = Color.white.opacity(0.08)
        public static let surfaceRaised = Color.white.opacity(0.14)
        public static let stroke = Color.white.opacity(0.10)
        public static let success = Color(red: 0.20, green: 0.78, blue: 0.35)
        public static let warning = Color(red: 1.00, green: 0.62, blue: 0.04)
        public static let danger = Color(red: 1.00, green: 0.27, blue: 0.23)
        public static let info = Color(red: 0.36, green: 0.62, blue: 1.00)
        public static let water = Color(red: 0.25, green: 0.62, blue: 1.00)
        public static let mindful = Color(red: 0.66, green: 0.52, blue: 1.00)
    }

    public enum Font {
        public static let title = SwiftUI.Font.system(size: 13, weight: .semibold)
        public static let body = SwiftUI.Font.system(size: 12)
        public static let label = SwiftUI.Font.system(size: 11, weight: .semibold)
        public static let caption = SwiftUI.Font.system(size: 10, weight: .medium)
        public static let figure = SwiftUI.Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()
    }

    /// "#RRGGBB" for `VehlaNotchActivity.tintHex`.
    public static func hex(_ r: Int, _ g: Int, _ b: Int) -> String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    public enum Hex {
        public static let success = "#33C759"
        public static let warning = "#FF9E0A"
        public static let danger = "#FF453A"
        public static let water = "#409EFF"
        public static let mindful = "#A885FF"
    }
}
