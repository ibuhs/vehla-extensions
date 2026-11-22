import Foundation

public struct TermColor: Equatable, Sendable {
    public enum Kind: UInt8, Sendable { case `default`, indexed, rgb }
    public var kind: Kind
    public var r: UInt8, g: UInt8, b: UInt8

    public static let `default` = TermColor(kind: .default, r: 0, g: 0, b: 0)
    public static func indexed(_ index: Int) -> TermColor { TermColor(kind: .indexed, r: UInt8(clamping: index), g: 0, b: 0) }
    public static func rgb(_ r: Int, _ g: Int, _ b: Int) -> TermColor {
        TermColor(kind: .rgb, r: UInt8(clamping: r), g: UInt8(clamping: g), b: UInt8(clamping: b))
    }
    public var index: Int { Int(r) }
}

public struct CellAttributes: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let bold = CellAttributes(rawValue: 1)
    public static let dim = CellAttributes(rawValue: 2)
    public static let italic = CellAttributes(rawValue: 4)
    public static let underline = CellAttributes(rawValue: 8)
    public static let inverse = CellAttributes(rawValue: 16)
    public static let strike = CellAttributes(rawValue: 32)
    public static let hidden = CellAttributes(rawValue: 64)
}

public struct TermCell: Equatable, Sendable {
    public var scalar: UInt32 = 0x20
    /// 1 normally, 2 for the left half of a wide character, 0 for its right half.
    public var width: UInt8 = 1
    public var fg: TermColor = .default
    public var bg: TermColor = .default
    public var attrs: CellAttributes = []
    public init() {}

    public var character: Character { Character(Unicode.Scalar(scalar) ?? " ") }
    public var isBlank: Bool { scalar == 0x20 && bg == .default && attrs.isEmpty }
}

public enum TerminalEvent: Equatable, Sendable {
    case bell
    case title(String)
    /// The shell's working directory (OSC 7).
    case cwd(String)
    /// The prompt is being drawn (OSC 133;A).
    case promptStart
    /// The text of the command about to run (private OSC 7777).
    case commandText(String)
    /// A command began executing (OSC 133;C).
    case commandStart
    /// A command finished, with its exit status when the shell reported one (OSC 133;D).
    case commandEnd(Int?)
}

enum CharacterWidth {
    /// Terminal column width: 0 for combining marks, 2 for East Asian wide characters and emoji, otherwise 1.
    static func of(_ scalar: UInt32) -> Int {
        if scalar < 0x20 || (0x7F..<0xA0).contains(scalar) { return 0 }
        if scalar < 0x300 { return 1 }
        if let s = Unicode.Scalar(scalar) {
            switch s.properties.generalCategory {
            case .nonspacingMark, .enclosingMark, .format: return 0
            default: break
            }
        }
        switch scalar {
        case 0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xA000...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE6F, 0xFF00...0xFF60,
             0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F900...0x1F9FF, 0x1FA70...0x1FAFF,
             0x20000...0x3FFFD:
            return 2
        default:
            return 1
        }
    }
}
