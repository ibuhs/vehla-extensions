import AppKit
import MiniTerminalCore

/// Colours for the terminal. The default is strictly black and white to match the Notch: every colour a program
/// asks for is mapped to a shade of grey, so output stays readable and distinct without introducing colour.
struct TerminalTheme: Identifiable, Equatable {
    enum Palette: Equatable {
        case grayscale
        case tinted(NSColor)
        case ansi([NSColor])
    }

    let id: String
    let name: String
    let foreground: NSColor
    let cursor: NSColor
    let selection: NSColor
    let palette: Palette
    /// A soft halo around the text, like a glowing CRT.
    var glow: NSColor?

    /// Fully transparent: the Notch's own black shows through.
    var background: NSColor { .clear }

    // xterm's 16 colours, used to judge how bright a colour is.
    private static let base16: [(Double, Double, Double)] = [
        (0, 0, 0), (0.80, 0.19, 0.19), (0.05, 0.74, 0.47), (0.90, 0.90, 0.06), (0.14, 0.45, 0.82), (0.74, 0.25, 0.74),
        (0.07, 0.66, 0.80), (0.90, 0.90, 0.90), (0.40, 0.40, 0.40), (0.95, 0.30, 0.30), (0.14, 0.82, 0.55),
        (0.96, 0.96, 0.26), (0.23, 0.56, 0.92), (0.84, 0.44, 0.84), (0.16, 0.72, 0.86), (1, 1, 1),
    ]

    private static let cube: [Double] = [0, 95, 135, 175, 215, 255].map { $0 / 255 }

    private func rgb(for color: TermColor) -> (Double, Double, Double) {
        switch color.kind {
        case .default: return (1, 1, 1)
        case .rgb: return (Double(color.r) / 255, Double(color.g) / 255, Double(color.b) / 255)
        case .indexed:
            let i = color.index
            if i < 16 { return Self.base16[i] }
            if i < 232 {
                let n = i - 16
                return (Self.cube[n / 36], Self.cube[(n / 6) % 6], Self.cube[n % 6])
            }
            let g = (8 + Double(i - 232) * 10) / 255
            return (g, g, g)
        }
    }

    private func luma(_ c: (Double, Double, Double)) -> Double { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }

    /// `nil` means the theme's default colour.
    func resolve(_ color: TermColor, foreground isForeground: Bool, bright: Bool) -> NSColor? {
        guard color.kind != .default else { return nil }
        var effective = color
        if bright, isForeground, color.kind == .indexed, color.index < 8 { effective = .indexed(color.index + 8) }
        switch palette {
        case .ansi(let colors):
            if effective.kind == .indexed, effective.index < 16 { return colors[effective.index] }
            let c = rgb(for: effective)
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        case .grayscale:
            let l = luma(rgb(for: effective))
            let g = isForeground ? 0.34 + 0.66 * l : 0.06 + 0.40 * l      // text never vanishes into the black
            return NSColor(white: g, alpha: 1)
        case .tinted(let tint):
            let l = luma(rgb(for: effective))
            let g = isForeground ? 0.38 + 0.62 * l : 0.06 + 0.34 * l
            return tint.scaled(g)
        }
    }

    static let mono = TerminalTheme(
        id: "mono", name: "Black & White", foreground: NSColor(white: 0.93, alpha: 1), cursor: NSColor(white: 0.97, alpha: 1),
        selection: NSColor(white: 1, alpha: 0.22), palette: .grayscale)

    static let color = TerminalTheme(
        id: "color", name: "Color", foreground: NSColor(white: 0.92, alpha: 1), cursor: NSColor(white: 0.97, alpha: 1),
        selection: NSColor(srgbRed: 0.42, green: 0.62, blue: 1, alpha: 0.35),
        palette: .ansi([
            "#5b6168", "#ff6b6b", "#7ee787", "#f4d35e", "#6cb6ff", "#d2a8ff", "#76e4f7", "#e6e6e6",
            "#8b939c", "#ff8f8f", "#9bf0a4", "#ffe08a", "#8cc8ff", "#e2c5ff", "#9ceeff", "#ffffff",
        ].map(NSColor.hex)))

    static let phosphor = TerminalTheme(
        id: "phosphor", name: "Phosphor", foreground: NSColor.hex("#7dff8a"), cursor: NSColor.hex("#b6ffbd"),
        selection: NSColor.hex("#7dff8a").withAlphaComponent(0.25), palette: .tinted(NSColor.hex("#7dff8a")))

    static let hacker = TerminalTheme(
        id: "hacker", name: "Hacker Green", foreground: NSColor.hex("#00ff41"), cursor: NSColor.hex("#4dff75"),
        selection: NSColor.hex("#00ff41").withAlphaComponent(0.28), palette: .tinted(NSColor.hex("#00ff41")),
        glow: NSColor.hex("#00ff41"))

    static let amber = TerminalTheme(
        id: "amber", name: "Amber", foreground: NSColor.hex("#ffb54a"), cursor: NSColor.hex("#ffd391"),
        selection: NSColor.hex("#ffb54a").withAlphaComponent(0.25), palette: .tinted(NSColor.hex("#ffb54a")))

    static let all = [mono, color, hacker, phosphor, amber]
    static func named(_ id: String?) -> TerminalTheme { all.first { $0.id == id } ?? .mono }
}

extension NSColor {
    static func hex(_ value: String) -> NSColor {
        let s = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        return NSColor(srgbRed: CGFloat((n >> 16) & 0xFF) / 255, green: CGFloat((n >> 8) & 0xFF) / 255,
                       blue: CGFloat(n & 0xFF) / 255, alpha: 1)
    }

    func scaled(_ factor: Double) -> NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        return NSColor(srgbRed: c.redComponent * factor, green: c.greenComponent * factor, blue: c.blueComponent * factor, alpha: 1)
    }
}
