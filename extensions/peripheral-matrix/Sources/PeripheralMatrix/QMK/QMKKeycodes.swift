import Foundation

struct QMKKeycodeOption: Identifiable, Equatable {
    let code: UInt16
    let name: String
    let label: String
    var id: UInt16 { code }
}
enum QMKKeycodes {
    // Basic HID and quantum ranges match the pinned Keychron/QMK firmware.
    static let basic: [QMKKeycodeOption] = [
        .init(code: 0x0000, name: "KC_NO", label: "None"),
        .init(code: 0x0001, name: "KC_TRANSPARENT", label: "Transparent"),
        .init(code: 0x0004, name: "KC_A", label: "A"),
        .init(code: 0x0005, name: "KC_B", label: "B"),
        .init(code: 0x0006, name: "KC_C", label: "C"),
        .init(code: 0x0007, name: "KC_D", label: "D"),
        .init(code: 0x0008, name: "KC_E", label: "E"),
        .init(code: 0x0009, name: "KC_F", label: "F"),
        .init(code: 0x000a, name: "KC_G", label: "G"),
        .init(code: 0x000b, name: "KC_H", label: "H"),
        .init(code: 0x000c, name: "KC_I", label: "I"),
        .init(code: 0x000d, name: "KC_J", label: "J"),
        .init(code: 0x000e, name: "KC_K", label: "K"),
        .init(code: 0x000f, name: "KC_L", label: "L"),
        .init(code: 0x0010, name: "KC_M", label: "M"),
        .init(code: 0x0011, name: "KC_N", label: "N"),
        .init(code: 0x0012, name: "KC_O", label: "O"),
        .init(code: 0x0013, name: "KC_P", label: "P"),
        .init(code: 0x0014, name: "KC_Q", label: "Q"),
        .init(code: 0x0015, name: "KC_R", label: "R"),
        .init(code: 0x0016, name: "KC_S", label: "S"),
        .init(code: 0x0017, name: "KC_T", label: "T"),
        .init(code: 0x0018, name: "KC_U", label: "U"),
        .init(code: 0x0019, name: "KC_V", label: "V"),
        .init(code: 0x001a, name: "KC_W", label: "W"),
        .init(code: 0x001b, name: "KC_X", label: "X"),
        .init(code: 0x001c, name: "KC_Y", label: "Y"),
        .init(code: 0x001d, name: "KC_Z", label: "Z"),
        .init(code: 0x001e, name: "KC_1", label: "1"),
        .init(code: 0x001f, name: "KC_2", label: "2"),
        .init(code: 0x0020, name: "KC_3", label: "3"),
        .init(code: 0x0021, name: "KC_4", label: "4"),
        .init(code: 0x0022, name: "KC_5", label: "5"),
        .init(code: 0x0023, name: "KC_6", label: "6"),
        .init(code: 0x0024, name: "KC_7", label: "7"),
        .init(code: 0x0025, name: "KC_8", label: "8"),
        .init(code: 0x0026, name: "KC_9", label: "9"),
        .init(code: 0x0027, name: "KC_0", label: "0"),
        .init(code: 0x0028, name: "KC_ENTER", label: "Enter"),
        .init(code: 0x0029, name: "KC_ESCAPE", label: "Esc"),
        .init(code: 0x002a, name: "KC_BACKSPACE", label: "Backspace"),
        .init(code: 0x002b, name: "KC_TAB", label: "Tab"),
        .init(code: 0x002c, name: "KC_SPACE", label: "Space"),
        .init(code: 0x002d, name: "KC_MINUS", label: "−"),
        .init(code: 0x002e, name: "KC_EQUAL", label: "="),
        .init(code: 0x002f, name: "KC_LEFT_BRACKET", label: "["),
        .init(code: 0x0030, name: "KC_RIGHT_BRACKET", label: "]"),
        .init(code: 0x0031, name: "KC_BACKSLASH", label: "\\"),
        .init(code: 0x0032, name: "KC_NONUS_HASH", label: "Nonus Hash"),
        .init(code: 0x0033, name: "KC_SEMICOLON", label: ";"),
        .init(code: 0x0034, name: "KC_QUOTE", label: "'"),
        .init(code: 0x0035, name: "KC_GRAVE", label: "`"),
        .init(code: 0x0036, name: "KC_COMMA", label: ","),
        .init(code: 0x0037, name: "KC_DOT", label: "."),
        .init(code: 0x0038, name: "KC_SLASH", label: "/"),
        .init(code: 0x0039, name: "KC_CAPS_LOCK", label: "Caps"),
        .init(code: 0x003a, name: "KC_F1", label: "F1"),
        .init(code: 0x003b, name: "KC_F2", label: "F2"),
        .init(code: 0x003c, name: "KC_F3", label: "F3"),
        .init(code: 0x003d, name: "KC_F4", label: "F4"),
        .init(code: 0x003e, name: "KC_F5", label: "F5"),
        .init(code: 0x003f, name: "KC_F6", label: "F6"),
        .init(code: 0x0040, name: "KC_F7", label: "F7"),
        .init(code: 0x0041, name: "KC_F8", label: "F8"),
        .init(code: 0x0042, name: "KC_F9", label: "F9"),
        .init(code: 0x0043, name: "KC_F10", label: "F10"),
        .init(code: 0x0044, name: "KC_F11", label: "F11"),
        .init(code: 0x0045, name: "KC_F12", label: "F12"),
        .init(code: 0x0046, name: "KC_PRINT_SCREEN", label: "Print Screen"),
        .init(code: 0x0047, name: "KC_SCROLL_LOCK", label: "Scroll Lock"),
        .init(code: 0x0048, name: "KC_PAUSE", label: "Pause"),
        .init(code: 0x0049, name: "KC_INSERT", label: "Insert"),
        .init(code: 0x004a, name: "KC_HOME", label: "Home"),
        .init(code: 0x004b, name: "KC_PAGE_UP", label: "Page Up"),
        .init(code: 0x004c, name: "KC_DELETE", label: "Delete"),
        .init(code: 0x004d, name: "KC_END", label: "End"),
        .init(code: 0x004e, name: "KC_PAGE_DOWN", label: "Page Down"),
        .init(code: 0x004f, name: "KC_RIGHT", label: "Right"),
        .init(code: 0x0050, name: "KC_LEFT", label: "Left"),
        .init(code: 0x0051, name: "KC_DOWN", label: "Down"),
        .init(code: 0x0052, name: "KC_UP", label: "Up"),
        .init(code: 0x0053, name: "KC_NUM_LOCK", label: "Num Lock"),
        .init(code: 0x0054, name: "KC_KP_SLASH", label: "Kp Slash"),
        .init(code: 0x0055, name: "KC_KP_ASTERISK", label: "Kp Asterisk"),
        .init(code: 0x0056, name: "KC_KP_MINUS", label: "Kp Minus"),
        .init(code: 0x0057, name: "KC_KP_PLUS", label: "Kp Plus"),
        .init(code: 0x0058, name: "KC_KP_ENTER", label: "Kp Enter"),
        .init(code: 0x0059, name: "KC_KP_1", label: "Kp 1"),
        .init(code: 0x005a, name: "KC_KP_2", label: "Kp 2"),
        .init(code: 0x005b, name: "KC_KP_3", label: "Kp 3"),
        .init(code: 0x005c, name: "KC_KP_4", label: "Kp 4"),
        .init(code: 0x005d, name: "KC_KP_5", label: "Kp 5"),
        .init(code: 0x005e, name: "KC_KP_6", label: "Kp 6"),
        .init(code: 0x005f, name: "KC_KP_7", label: "Kp 7"),
        .init(code: 0x0060, name: "KC_KP_8", label: "Kp 8"),
        .init(code: 0x0061, name: "KC_KP_9", label: "Kp 9"),
        .init(code: 0x0062, name: "KC_KP_0", label: "Kp 0"),
        .init(code: 0x0063, name: "KC_KP_DOT", label: "Kp Dot"),
        .init(code: 0x0064, name: "KC_NONUS_BACKSLASH", label: "Nonus Backslash"),
        .init(code: 0x0065, name: "KC_APPLICATION", label: "Application"),
        .init(code: 0x0066, name: "KC_KB_POWER", label: "Kb Power"),
        .init(code: 0x0067, name: "KC_KP_EQUAL", label: "Kp Equal"),
        .init(code: 0x0068, name: "KC_F13", label: "F13"),
        .init(code: 0x0069, name: "KC_F14", label: "F14"),
        .init(code: 0x006a, name: "KC_F15", label: "F15"),
        .init(code: 0x006b, name: "KC_F16", label: "F16"),
        .init(code: 0x006c, name: "KC_F17", label: "F17"),
        .init(code: 0x006d, name: "KC_F18", label: "F18"),
        .init(code: 0x006e, name: "KC_F19", label: "F19"),
        .init(code: 0x006f, name: "KC_F20", label: "F20"),
        .init(code: 0x0070, name: "KC_F21", label: "F21"),
        .init(code: 0x0071, name: "KC_F22", label: "F22"),
        .init(code: 0x0072, name: "KC_F23", label: "F23"),
        .init(code: 0x0073, name: "KC_F24", label: "F24"),
        .init(code: 0x0074, name: "KC_EXECUTE", label: "Execute"),
        .init(code: 0x0075, name: "KC_HELP", label: "Help"),
        .init(code: 0x0076, name: "KC_MENU", label: "Menu"),
        .init(code: 0x0077, name: "KC_SELECT", label: "Select"),
        .init(code: 0x0078, name: "KC_STOP", label: "Stop"),
        .init(code: 0x0079, name: "KC_AGAIN", label: "Again"),
        .init(code: 0x007a, name: "KC_UNDO", label: "Undo"),
        .init(code: 0x007b, name: "KC_CUT", label: "Cut"),
        .init(code: 0x007c, name: "KC_COPY", label: "Copy"),
        .init(code: 0x007d, name: "KC_PASTE", label: "Paste"),
        .init(code: 0x007e, name: "KC_FIND", label: "Find"),
        .init(code: 0x007f, name: "KC_KB_MUTE", label: "Kb Mute"),
        .init(code: 0x0080, name: "KC_KB_VOLUME_UP", label: "Kb Volume Up"),
        .init(code: 0x0081, name: "KC_KB_VOLUME_DOWN", label: "Kb Volume Down"),
        .init(code: 0x0082, name: "KC_LOCKING_CAPS_LOCK", label: "Locking Caps Lock"),
        .init(code: 0x0083, name: "KC_LOCKING_NUM_LOCK", label: "Locking Num Lock"),
        .init(code: 0x0084, name: "KC_LOCKING_SCROLL_LOCK", label: "Locking Scroll Lock"),
        .init(code: 0x0085, name: "KC_KP_COMMA", label: "Kp Comma"),
        .init(code: 0x0086, name: "KC_KP_EQUAL_AS400", label: "Kp Equal As400"),
        .init(code: 0x0087, name: "KC_INTERNATIONAL_1", label: "International 1"),
        .init(code: 0x0088, name: "KC_INTERNATIONAL_2", label: "International 2"),
        .init(code: 0x0089, name: "KC_INTERNATIONAL_3", label: "International 3"),
        .init(code: 0x008a, name: "KC_INTERNATIONAL_4", label: "International 4"),
        .init(code: 0x008b, name: "KC_INTERNATIONAL_5", label: "International 5"),
        .init(code: 0x008c, name: "KC_INTERNATIONAL_6", label: "International 6"),
        .init(code: 0x008d, name: "KC_INTERNATIONAL_7", label: "International 7"),
        .init(code: 0x008e, name: "KC_INTERNATIONAL_8", label: "International 8"),
        .init(code: 0x008f, name: "KC_INTERNATIONAL_9", label: "International 9"),
        .init(code: 0x0090, name: "KC_LANGUAGE_1", label: "Language 1"),
        .init(code: 0x0091, name: "KC_LANGUAGE_2", label: "Language 2"),
        .init(code: 0x0092, name: "KC_LANGUAGE_3", label: "Language 3"),
        .init(code: 0x0093, name: "KC_LANGUAGE_4", label: "Language 4"),
        .init(code: 0x0094, name: "KC_LANGUAGE_5", label: "Language 5"),
        .init(code: 0x0095, name: "KC_LANGUAGE_6", label: "Language 6"),
        .init(code: 0x0096, name: "KC_LANGUAGE_7", label: "Language 7"),
        .init(code: 0x0097, name: "KC_LANGUAGE_8", label: "Language 8"),
        .init(code: 0x0098, name: "KC_LANGUAGE_9", label: "Language 9"),
        .init(code: 0x0099, name: "KC_ALTERNATE_ERASE", label: "Alternate Erase"),
        .init(code: 0x009a, name: "KC_SYSTEM_REQUEST", label: "System Request"),
        .init(code: 0x009b, name: "KC_CANCEL", label: "Cancel"),
        .init(code: 0x009c, name: "KC_CLEAR", label: "Clear"),
        .init(code: 0x009d, name: "KC_PRIOR", label: "Prior"),
        .init(code: 0x009e, name: "KC_RETURN", label: "Return"),
        .init(code: 0x009f, name: "KC_SEPARATOR", label: "Separator"),
        .init(code: 0x00a0, name: "KC_OUT", label: "Out"),
        .init(code: 0x00a1, name: "KC_OPER", label: "Oper"),
        .init(code: 0x00a2, name: "KC_CLEAR_AGAIN", label: "Clear Again"),
        .init(code: 0x00a3, name: "KC_CRSEL", label: "Crsel"),
        .init(code: 0x00a4, name: "KC_EXSEL", label: "Exsel"),
        .init(code: 0x00a5, name: "KC_SYSTEM_POWER", label: "System Power"),
        .init(code: 0x00a6, name: "KC_SYSTEM_SLEEP", label: "System Sleep"),
        .init(code: 0x00a7, name: "KC_SYSTEM_WAKE", label: "System Wake"),
        .init(code: 0x00a8, name: "KC_AUDIO_MUTE", label: "Mute"),
        .init(code: 0x00a9, name: "KC_AUDIO_VOL_UP", label: "Vol +"),
        .init(code: 0x00aa, name: "KC_AUDIO_VOL_DOWN", label: "Vol −"),
        .init(code: 0x00ab, name: "KC_MEDIA_NEXT_TRACK", label: "Next"),
        .init(code: 0x00ac, name: "KC_MEDIA_PREV_TRACK", label: "Previous"),
        .init(code: 0x00ad, name: "KC_MEDIA_STOP", label: "Media Stop"),
        .init(code: 0x00ae, name: "KC_MEDIA_PLAY_PAUSE", label: "Play/Pause"),
        .init(code: 0x00af, name: "KC_MEDIA_SELECT", label: "Media Select"),
        .init(code: 0x00b0, name: "KC_MEDIA_EJECT", label: "Media Eject"),
        .init(code: 0x00b1, name: "KC_MAIL", label: "Mail"),
        .init(code: 0x00b2, name: "KC_CALCULATOR", label: "Calculator"),
        .init(code: 0x00b3, name: "KC_MY_COMPUTER", label: "My Computer"),
        .init(code: 0x00b4, name: "KC_WWW_SEARCH", label: "Www Search"),
        .init(code: 0x00b5, name: "KC_WWW_HOME", label: "Www Home"),
        .init(code: 0x00b6, name: "KC_WWW_BACK", label: "Www Back"),
        .init(code: 0x00b7, name: "KC_WWW_FORWARD", label: "Www Forward"),
        .init(code: 0x00b8, name: "KC_WWW_STOP", label: "Www Stop"),
        .init(code: 0x00b9, name: "KC_WWW_REFRESH", label: "Www Refresh"),
        .init(code: 0x00ba, name: "KC_WWW_FAVORITES", label: "Www Favorites"),
        .init(code: 0x00bb, name: "KC_MEDIA_FAST_FORWARD", label: "Media Fast Forward"),
        .init(code: 0x00bc, name: "KC_MEDIA_REWIND", label: "Media Rewind"),
        .init(code: 0x00bd, name: "KC_BRIGHTNESS_UP", label: "Brightness Up"),
        .init(code: 0x00be, name: "KC_BRIGHTNESS_DOWN", label: "Brightness Down"),
        .init(code: 0x00bf, name: "KC_CONTROL_PANEL", label: "Control Panel"),
        .init(code: 0x00c0, name: "KC_ASSISTANT", label: "Assistant"),
        .init(code: 0x00c1, name: "KC_MISSION_CONTROL", label: "Mission Control"),
        .init(code: 0x00c2, name: "KC_LAUNCHPAD", label: "Launchpad"),
        .init(code: 0x00cd, name: "KC_MS_UP", label: "Ms Up"),
        .init(code: 0x00ce, name: "KC_MS_DOWN", label: "Ms Down"),
        .init(code: 0x00cf, name: "KC_MS_LEFT", label: "Ms Left"),
        .init(code: 0x00d0, name: "KC_MS_RIGHT", label: "Ms Right"),
        .init(code: 0x00d1, name: "KC_MS_BTN1", label: "Ms Btn1"),
        .init(code: 0x00d2, name: "KC_MS_BTN2", label: "Ms Btn2"),
        .init(code: 0x00d3, name: "KC_MS_BTN3", label: "Ms Btn3"),
        .init(code: 0x00d4, name: "KC_MS_BTN4", label: "Ms Btn4"),
        .init(code: 0x00d5, name: "KC_MS_BTN5", label: "Ms Btn5"),
        .init(code: 0x00d6, name: "KC_MS_BTN6", label: "Ms Btn6"),
        .init(code: 0x00d7, name: "KC_MS_BTN7", label: "Ms Btn7"),
        .init(code: 0x00d8, name: "KC_MS_BTN8", label: "Ms Btn8"),
        .init(code: 0x00d9, name: "KC_MS_WH_UP", label: "Ms Wh Up"),
        .init(code: 0x00da, name: "KC_MS_WH_DOWN", label: "Ms Wh Down"),
        .init(code: 0x00db, name: "KC_MS_WH_LEFT", label: "Ms Wh Left"),
        .init(code: 0x00dc, name: "KC_MS_WH_RIGHT", label: "Ms Wh Right"),
        .init(code: 0x00dd, name: "KC_MS_ACCEL0", label: "Ms Accel0"),
        .init(code: 0x00de, name: "KC_MS_ACCEL1", label: "Ms Accel1"),
        .init(code: 0x00df, name: "KC_MS_ACCEL2", label: "Ms Accel2"),
        .init(code: 0x00e0, name: "KC_LEFT_CTRL", label: "Ctrl"),
        .init(code: 0x00e1, name: "KC_LEFT_SHIFT", label: "Shift"),
        .init(code: 0x00e2, name: "KC_LEFT_ALT", label: "Option"),
        .init(code: 0x00e3, name: "KC_LEFT_GUI", label: "Cmd"),
        .init(code: 0x00e4, name: "KC_RIGHT_CTRL", label: "R Ctrl"),
        .init(code: 0x00e5, name: "KC_RIGHT_SHIFT", label: "R Shift"),
        .init(code: 0x00e6, name: "KC_RIGHT_ALT", label: "R Option"),
        .init(code: 0x00e7, name: "KC_RIGHT_GUI", label: "R Cmd"),
    ]
    static let custom: [QMKKeycodeOption] = [
        .init(code: 0x7e00, name: "Keychron: Mission Control", label: "Mission Control"),
        .init(code: 0x7e01, name: "Keychron: Launchpad", label: "Launchpad"),
        .init(code: 0x7e02, name: "Keychron: Left Option", label: "Left Option"),
        .init(code: 0x7e03, name: "Keychron: Right Option", label: "Right Option"),
        .init(code: 0x7e04, name: "Keychron: Left Cmd", label: "Left Cmd"),
        .init(code: 0x7e05, name: "Keychron: Right Cmd", label: "Right Cmd"),
        .init(code: 0x7e06, name: "Keychron: Task View", label: "Task View"),
        .init(code: 0x7e07, name: "Keychron: File Explorer", label: "File Explorer"),
        .init(code: 0x7e08, name: "Keychron: Screenshot", label: "Screenshot"),
        .init(code: 0x7e09, name: "Keychron: Cortana", label: "Cortana"),
        .init(code: 0x7e0a, name: "Keychron: Siri", label: "Siri"),
        .init(code: 0x7e0b, name: "Keychron: Bluetooth 1", label: "Bluetooth 1"),
        .init(code: 0x7e0c, name: "Keychron: Bluetooth 2", label: "Bluetooth 2"),
        .init(code: 0x7e0d, name: "Keychron: Bluetooth 3", label: "Bluetooth 3"),
        .init(code: 0x7e0e, name: "Keychron: Battery", label: "Battery"),
    ]
    static let macros = (0..<16).map { QMKKeycodeOption(code: UInt16(0x7700 + $0), name: "Existing macro \($0 + 1)", label: "M\($0 + 1)") }
    static let options = basic + custom + macros
    static func options(for profile: QMKKeyboardProfile?) -> [QMKKeycodeOption] {
        guard let profile, !profile.customNames.isEmpty else { return options }
        return basic + profile.customNames.enumerated().map {
            QMKKeycodeOption(code: UInt16(0x7e00 + $0.offset), name: "Keychron: " + $0.element, label: $0.element)
        } + macros
    }
    static func label(_ code: UInt16, profile: QMKKeyboardProfile?) -> String {
        if (0x7e00...0x7e3f).contains(code), let profile, !profile.customNames.isEmpty {
            return options(for: profile).first { $0.code == code }?.label ?? String(format: "0x%04X", code)
        }
        return label(code)
    }
    static func label(_ code: UInt16) -> String {
        if let known = options.first(where: { $0.code == code }) { return known.label }
        let base = code & 0xffe0, layer = Int(code & 0x1f)
        if let name = [UInt16(0x5200): "TO", 0x5220: "MO", 0x5240: "DF", 0x5260: "TG", 0x5280: "OSL"][base] { return "\(name)(\(layer))" }
        if code >= 0x0100 && code <= 0x1fff {
            let mods = code >> 8
            let symbols = [(UInt16(1), "⌃"), (2, "⇧"), (4, "⌥"), (8, "⌘")].filter { mods & $0.0 != 0 }.map(\.1).joined()
            return symbols + label(code & 0xff)
        }
        return String(format: "0x%04X", code)
    }
    static func parse(_ text: String, profile: QMKKeyboardProfile? = nil) -> UInt16? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let aliases: [String: UInt16] = ["KC_TRNS": 1, "_______": 1, "XXXXXXX": 0, "KC_ENT": 0x28, "KC_ESC": 0x29, "KC_BSPC": 0x2a, "KC_SPC": 0x2c, "KC_LCTL": 0xe0, "KC_LSFT": 0xe1, "KC_LALT": 0xe2, "KC_LGUI": 0xe3]
        if let alias = aliases[trimmed] { return alias }
        if let opening = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")"), let layer = Int(trimmed[trimmed.index(after: opening)..<trimmed.index(before: trimmed.endIndex)]) {
            return layerAction(String(trimmed[..<opening]), layer: layer, count: 32)
        }
        if let named = options(for: profile).first(where: { $0.name.uppercased() == trimmed }) { return named.code }
        guard trimmed.hasPrefix("0X"), trimmed.count >= 3, trimmed.count <= 6 else { return nil }
        return UInt16(trimmed.dropFirst(2), radix: 16)
    }
    static func layerAction(_ action: String, layer: Int, count: Int) -> UInt16? {
        guard (0..<count).contains(layer), let base = ["MO": UInt16(0x5220), "TO": 0x5200, "TG": 0x5260, "DF": 0x5240, "OSL": 0x5280][action] else { return nil }
        return base | UInt16(layer)
    }
    static func shortcut(_ code: UInt16, modifiers: UInt16) -> UInt16? {
        guard code > 1, code <= 0xff, modifiers <= 0x0f else { return nil }
        return modifiers << 8 | code
    }
    static func validate(_ code: UInt16, layerCount: Int, macroCount: Int? = nil) throws {
        if let macroCount, (0x7700...0x777f).contains(code), Int(code - 0x7700) >= macroCount {
            throw VIAError.message("That macro slot does not exist on this keyboard.")
        }
        if (0x5200...0x529f).contains(code), Int(code & 0x1f) >= layerCount {
            throw VIAError.message("That action refers to a layer the firmware does not contain.")
        }
        if (0x4000...0x4fff).contains(code), Int((code >> 8) & 0x0f) >= layerCount {
            throw VIAError.message("Layer-tap refers to a layer the firmware does not contain.")
        }
    }
}
