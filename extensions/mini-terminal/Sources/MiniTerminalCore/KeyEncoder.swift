import Foundation

public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shift = KeyModifiers(rawValue: 1)
    public static let control = KeyModifiers(rawValue: 2)
    public static let option = KeyModifiers(rawValue: 4)
    public static let command = KeyModifiers(rawValue: 8)
}

public enum TerminalKey: Equatable, Sendable {
    case character(String)
    case enter, tab, backTab, escape, backspace, forwardDelete
    case up, down, left, right, home, end, pageUp, pageDown
    case function(Int)
}

/// Turns keystrokes and pastes into the bytes a terminal program expects.
public enum KeyEncoder {
    private static let esc: UInt8 = 0x1B

    public static func encode(_ key: TerminalKey, modifiers m: KeyModifiers = [], applicationCursor: Bool = false) -> [UInt8] {
        switch key {
        case .character(let text): return character(text, m)
        case .enter: return [0x0D]
        case .tab: return [0x09]
        case .backTab: return [esc, 0x5B, 0x5A]
        case .escape: return [esc]
        case .backspace:
            if m.contains(.command) { return [0x15] }               // Cmd+Delete: delete to the start of the line
            if m.contains(.option) { return [esc, 0x7F] }            // Option+Delete: delete the previous word
            return m.contains(.control) ? [0x08] : [0x7F]
        case .forwardDelete: return csi("3", "~", m)
        case .up: return arrow("A", m, applicationCursor)
        case .down: return arrow("B", m, applicationCursor)
        case .right:
            if m.contains(.command) { return [0x05] }                // Cmd+→: end of line
            if m == .option { return [esc, UInt8(ascii: "f")] }      // Option+→: forward a word
            return arrow("C", m, applicationCursor)
        case .left:
            if m.contains(.command) { return [0x01] }                // Cmd+←: start of line
            if m == .option { return [esc, UInt8(ascii: "b")] }
            return arrow("D", m, applicationCursor)
        case .home: return applicationCursor && m.isEmpty ? [esc, 0x4F, 0x48] : csi("1", "H", m, bareWhenPlain: true)
        case .end: return applicationCursor && m.isEmpty ? [esc, 0x4F, 0x46] : csi("1", "F", m, bareWhenPlain: true)
        case .pageUp: return csi("5", "~", m)
        case .pageDown: return csi("6", "~", m)
        case .function(let n): return functionKey(n, m)
        }
    }

    private static func modifierCode(_ m: KeyModifiers) -> Int {
        1 + (m.contains(.shift) ? 1 : 0) + (m.contains(.option) ? 2 : 0) + (m.contains(.control) ? 4 : 0)
    }

    private static func arrow(_ letter: String, _ m: KeyModifiers, _ app: Bool) -> [UInt8] {
        let code = modifierCode(m)
        if code > 1 { return Array("\u{1B}[1;\(code)\(letter)".utf8) }
        return Array((app ? "\u{1B}O\(letter)" : "\u{1B}[\(letter)").utf8)
    }

    private static func csi(_ number: String, _ final: String, _ m: KeyModifiers, bareWhenPlain: Bool = false) -> [UInt8] {
        let code = modifierCode(m)
        if code > 1 { return Array("\u{1B}[\(number);\(code)\(final)".utf8) }
        return Array((bareWhenPlain ? "\u{1B}[\(final)" : "\u{1B}[\(number)\(final)").utf8)
    }

    private static func functionKey(_ n: Int, _ m: KeyModifiers) -> [UInt8] {
        let ss3 = ["P", "Q", "R", "S"]
        let tilde = [5: 15, 6: 17, 7: 18, 8: 19, 9: 20, 10: 21, 11: 23, 12: 24]
        let code = modifierCode(m)
        if (1...4).contains(n) {
            return Array((code > 1 ? "\u{1B}[1;\(code)\(ss3[n - 1])" : "\u{1B}O\(ss3[n - 1])").utf8)
        }
        guard let number = tilde[n] else { return [] }
        return Array((code > 1 ? "\u{1B}[\(number);\(code)~" : "\u{1B}[\(number)~").utf8)
    }

    private static func character(_ text: String, _ m: KeyModifiers) -> [UInt8] {
        guard let first = text.unicodeScalars.first else { return [] }
        if m.contains(.command) { return [] }                         // Cmd shortcuts belong to the app
        var bytes: [UInt8]
        if m.contains(.control), text.unicodeScalars.count == 1 {
            switch first.value {
            case 0x61...0x7A: bytes = [UInt8(first.value - 0x60)]      // a-z
            case 0x41...0x5A: bytes = [UInt8(first.value - 0x40)]      // A-Z
            case 0x40, 0x20, 0x32: bytes = [0]                         // @ space 2
            case 0x5B, 0x33: bytes = [0x1B]                            // [ 3
            case 0x5C, 0x34: bytes = [0x1C]                            // \ 4
            case 0x5D, 0x35: bytes = [0x1D]                            // ] 5
            case 0x5E, 0x36: bytes = [0x1E]                            // ^ 6
            case 0x5F, 0x2D, 0x37: bytes = [0x1F]                      // _ - 7
            case 0x3F, 0x38: bytes = [0x7F]                            // ? 8
            default: bytes = Array(text.utf8)
            }
        } else {
            bytes = Array(text.utf8)
        }
        return m.contains(.option) ? [esc] + bytes : bytes              // Option acts as Meta
    }

    /// Text to send for a paste. Line breaks become returns. In bracketed mode the text is wrapped so the shell
    /// knows it was pasted, and escape characters are removed so pasted text can't end the paste early or
    /// inject commands.
    public static func paste(_ text: String, bracketed: Bool) -> [UInt8] {
        var cleaned = text.replacingOccurrences(of: "\r\n", with: "\r").replacingOccurrences(of: "\n", with: "\r")
        if bracketed {
            cleaned = cleaned.replacingOccurrences(of: "\u{1B}", with: "")
            return Array("\u{1B}[200~".utf8) + Array(cleaned.utf8) + Array("\u{1B}[201~".utf8)
        }
        return Array(cleaned.utf8)
    }
}

public enum ShellQuote {
    /// A path or word made safe to paste into a shell command line.
    public static func quote(_ text: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:@%+=,~")
        if !text.isEmpty, text.unicodeScalars.allSatisfy({ safe.contains($0) }) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
