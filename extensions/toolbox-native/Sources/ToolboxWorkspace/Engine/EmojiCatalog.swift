import Foundation

enum EmojiCatalog {
    /// Common GitHub/gemoji-style shortcodes.
    static let shortcodes: [String: String] = [
        "smile": "😄", "smiley": "😃", "grinning": "😀", "laughing": "😆", "laugh": "😂",
        "joy": "😂", "rofl": "🤣", "wink": "😉", "blush": "😊", "heart_eyes": "😍",
        "kissing_heart": "😘", "thinking": "🤔", "neutral_face": "😐", "expressionless": "😑",
        "sweat_smile": "😅", "sweat": "😓", "cry": "😢", "sob": "😭", "angry": "😠",
        "rage": "😡", "triumph": "😤", "sleepy": "😪", "sunglasses": "😎", "nerd": "🤓",
        "zipper_mouth": "🤐", "hugs": "🤗", "wave": "👋", "thumbsup": "👍", "+1": "👍",
        "thumbsdown": "👎", "-1": "👎", "clap": "👏", "pray": "🙏", "muscle": "💪",
        "ok_hand": "👌", "point_up": "☝️", "point_right": "👉", "point_left": "👈",
        "eyes": "👀", "brain": "🧠", "heart": "❤️", "orange_heart": "🧡", "yellow_heart": "💛",
        "green_heart": "💚", "blue_heart": "💙", "purple_heart": "💜", "black_heart": "🖤",
        "broken_heart": "💔", "sparkles": "✨", "star": "⭐", "fire": "🔥", "boom": "💥",
        "zap": "⚡", "sunny": "☀️", "cloud": "☁️", "umbrella": "☔", "snowflake": "❄️",
        "rainbow": "🌈", "earth_americas": "🌎", "rocket": "🚀", "airplane": "✈️",
        "car": "🚗", "bike": "🚲", "bus": "🚌", "train": "🚆", "ship": "🚢",
        "computer": "💻", "keyboard": "⌨️", "iphone": "📱", "email": "📧", "mailbox": "📫",
        "bulb": "💡", "flashlight": "🔦", "book": "📖", "books": "📚", "memo": "📝",
        "pencil": "✏️", "mag": "🔍", "lock": "🔒", "unlock": "🔓", "key": "🔑",
        "hammer": "🔨", "wrench": "🔧", "gear": "⚙️", "link": "🔗", "paperclip": "📎",
        "file_folder": "📁", "open_file_folder": "📂", "calendar": "📅", "pushpin": "📌",
        "round_pushpin": "📍", "warning": "⚠️", "no_entry": "⛔", "x": "❌", "check": "✅",
        "white_check_mark": "✅", "heavy_check_mark": "✔️", "question": "❓", "exclamation": "❗",
        "bangbang": "‼️", "interrobang": "⁉️", "100": "💯", "tada": "🎉", "confetti_ball": "🎊",
        "balloon": "🎈", "gift": "🎁", "trophy": "🏆", "medal": "🏅", "sports_medal": "🎖️",
        "soccer": "⚽", "basketball": "🏀", "football": "🏈", "baseball": "⚾", "tennis": "🎾",
        "coffee": "☕", "tea": "🍵", "beer": "🍺", "wine_glass": "🍷", "pizza": "🍕",
        "hamburger": "🍔", "fries": "🍟", "apple": "🍎", "banana": "🍌", "cookie": "🍪",
        "dog": "🐶", "cat": "🐱", "mouse": "🐭", "hamster": "🐹", "rabbit": "🐰",
        "fox": "🦊", "bear": "🐻", "panda": "🐼", "koala": "🐨", "tiger": "🐯",
        "lion": "🦁", "cow": "🐮", "pig": "🐷", "frog": "🐸", "monkey": "🐵",
        "chicken": "🐔", "penguin": "🐧", "bird": "🐦", "baby_chick": "🐤", "hatching_chick": "🐣",
        "snake": "🐍", "turtle": "🐢", "fish": "🐟", "whale": "🐳", "dolphin": "🐬",
        "bug": "🐛", "bee": "🐝", "butterfly": "🦋", "flower": "🌸", "rose": "🌹",
        "sunflower": "🌻", "hibiscus": "🌺", "maple_leaf": "🍁", "leaves": "🍃", "seedling": "🌱",
        "tree": "🌳", "palm_tree": "🌴", "cactus": "🌵", "mushroom": "🍄", "globe_with_meridians": "🌐",
        "new": "🆕", "free": "🆓", "sos": "🆘", "up": "🆙", "vs": "🆚",
        "abc": "🔤", "abcd": "🔡", "1234": "🔢", "hash": "#️⃣", "asterisk": "*️⃣",
        "zero": "0️⃣", "one": "1️⃣", "two": "2️⃣", "three": "3️⃣", "four": "4️⃣",
        "five": "5️⃣", "six": "6️⃣", "seven": "7️⃣", "eight": "8️⃣", "nine": "9️⃣",
        "keycap_ten": "🔟", "arrow_right": "➡️", "arrow_left": "⬅️", "arrow_up": "⬆️",
        "arrow_down": "⬇️", "arrows_counterclockwise": "🔄", "recycle": "♻️", "infinity": "♾️",
        "tm": "™️", "copyright": "©️", "registered": "®️", "heavy_dollar_sign": "💲",
        "currency_exchange": "💱", "chart": "📈", "bar_chart": "📊", "clipboard": "📋",
        "package": "📦", "mailbox_with_mail": "📬", "inbox_tray": "📥", "outbox_tray": "📤",
        "hourglass": "⌛", "hourglass_flowing_sand": "⏳", "alarm_clock": "⏰", "watch": "⌚",
        "stopwatch": "⏱️", "timer_clock": "⏲️", "bell": "🔔", "no_bell": "🔕",
        "mega": "📣", "loudspeaker": "📢", "speech_balloon": "💬", "thought_balloon": "💭",
        "zzz": "💤", "poop": "💩", "ghost": "👻", "skull": "💀", "robot": "🤖",
        "alien": "👽", "space_invader": "👾", "jack_o_lantern": "🎃", "christmas_tree": "🎄",
        "sparkler": "🎇", "fireworks": "🎆", "ticket": "🎫", "cinema": "🎦", "movie_camera": "🎥",
        "camera": "📷", "video_camera": "📹", "tv": "📺", "radio": "📻", "microphone": "🎤",
        "headphones": "🎧", "musical_note": "🎵", "notes": "🎶", "guitar": "🎸", "drum": "🥁",
    ]

    private static let reverse: [String: String] = {
        var map: [String: String] = [:]
        for (code, emoji) in shortcodes {
            map[emoji] = code
        }
        return map
    }()

    static func encode(_ text: String) -> String {
        var result = text
        let pattern = #":([a-z0-9_+-]+):"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            guard match.numberOfRanges == 2,
                  let full = Range(match.range, in: result),
                  let nameRange = Range(match.range(at: 1), in: result)
            else { continue }
            let name = String(result[nameRange])
            if let emoji = shortcodes[name] {
                result.replaceSubrange(full, with: emoji)
            }
        }
        return result
    }

    static func decode(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            var matched = false
            // Prefer longer emoji sequences first (ZWJ / variation selectors).
            for length in [8, 7, 6, 5, 4, 3, 2, 1] {
                guard let end = text.index(index, offsetBy: length, limitedBy: text.endIndex) else { continue }
                let slice = String(text[index..<end])
                if let code = reverse[slice] {
                    result += ":\(code):"
                    index = end
                    matched = true
                    break
                }
            }
            if !matched {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }
}
