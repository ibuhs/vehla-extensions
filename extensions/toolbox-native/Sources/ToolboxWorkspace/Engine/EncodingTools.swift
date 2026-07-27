import Foundation

actor EncodingTools {
    func run(_ request: ToolRequest) throws -> ToolOutput {
        let mode = (request.options["mode"] ?? "encode").lowercased()
        let encode = !mode.contains("decode")
        switch request.toolID {
        case "enc.base64":
            if encode {
                return ToolOutput(Data(request.primary.utf8).base64EncodedString())
            }
            guard let data = Data(base64Encoded: request.primary.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.invalidInput("Invalid Base64.")
            }
            return ToolOutput(String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined())
        case "enc.url":
            if encode {
                return ToolOutput(request.primary.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? request.primary)
            }
            return ToolOutput(request.primary.removingPercentEncoding ?? request.primary)
        case "enc.html":
            return ToolOutput(encode ? htmlEncode(request.primary) : htmlDecode(request.primary))
        case "enc.unicode":
            return ToolOutput(unicodeDump(request.primary))
        case "enc.ascii":
            return ToolOutput(asciiDump(request.primary))
        case "enc.binary":
            return try ToolOutput(encode ? toBinary(request.primary) : fromBinary(request.primary))
        case "enc.hex":
            return try ToolOutput(encode ? toHex(request.primary) : fromHex(request.primary))
        case "enc.octal":
            return try ToolOutput(encode ? toOctal(request.primary) : fromOctal(request.primary))
        case "enc.percent":
            if encode {
                var allowed = CharacterSet.alphanumerics
                allowed.insert(charactersIn: "-._~")
                return ToolOutput(request.primary.addingPercentEncoding(withAllowedCharacters: allowed) ?? request.primary)
            }
            return ToolOutput(request.primary.removingPercentEncoding ?? request.primary)
        case "enc.emoji":
            return ToolOutput(encode ? emojiEncode(request.primary) : emojiDecode(request.primary))
        case "enc.morse":
            return try ToolOutput(encode ? Morse.encode(request.primary) : Morse.decode(request.primary))
        case "enc.rot13":
            return ToolOutput(rot13(request.primary))
        case "enc.base32":
            return try ToolOutput(encode ? BaseN.encode(request.primary, alphabet: BaseN.base32) : BaseN.decode(request.primary, alphabet: BaseN.base32))
        case "enc.base58":
            return try ToolOutput(encode ? BaseN.encode(request.primary, alphabet: BaseN.base58) : BaseN.decode(request.primary, alphabet: BaseN.base58))
        case "enc.base62":
            return try ToolOutput(encode ? BaseN.encode(request.primary, alphabet: BaseN.base62) : BaseN.decode(request.primary, alphabet: BaseN.base62))
        case "enc.base85", "enc.ascii85":
            return try ToolOutput(encode ? Ascii85.encode(request.primary) : Ascii85.decode(request.primary))
        case "enc.base91":
            return try ToolOutput(encode ? Base91.encode(request.primary) : Base91.decode(request.primary))
        case "enc.urlParser":
            return try ToolOutput(parseURL(request.primary))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func htmlEncode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func htmlDecode(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private func unicodeDump(_ text: String) -> String {
        text.unicodeScalars.enumerated().map { index, scalar in
            let hex = String(scalar.value, radix: 16, uppercase: true)
            return "[\(index)] U+\(hex.padLeft(to: 4, with: "0")) \(scalar)"
        }.joined(separator: "\n")
    }

    private func asciiDump(_ text: String) -> String {
        text.utf8.map { byte in
            let printable = (32...126).contains(byte) ? String(UnicodeScalar(byte)) : "."
            return String(format: "%3d 0x%02X %@", byte, byte, printable)
        }.joined(separator: "\n")
    }

    private func toBinary(_ text: String) -> String {
        text.utf8.map { String($0, radix: 2).padLeft(to: 8, with: "0") }.joined(separator: " ")
    }

    private func fromBinary(_ text: String) throws -> String {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        var data = Data()
        for part in parts {
            guard let value = UInt8(part, radix: 2) else {
                throw ToolError.invalidInput("Invalid binary byte: \(part)")
            }
            data.append(value)
        }
        return String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()
    }

    private func toHex(_ text: String) -> String {
        text.utf8.map { String(format: "%02x", $0) }.joined()
    }

    private func fromHex(_ text: String) throws -> String {
        let data = try BinaryCodec.decodeData(text)
        return String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()
    }

    private func toOctal(_ text: String) -> String {
        text.utf8.map { String($0, radix: 8).padLeft(to: 3, with: "0") }.joined(separator: " ")
    }

    private func fromOctal(_ text: String) throws -> String {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\n" })
        var data = Data()
        for part in parts {
            guard let value = UInt8(part, radix: 8) else {
                throw ToolError.invalidInput("Invalid octal byte: \(part)")
            }
            data.append(value)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func emojiEncode(_ text: String) -> String {
        EmojiCatalog.encode(text)
    }

    private func emojiDecode(_ text: String) -> String {
        EmojiCatalog.decode(text)
    }

    private func rot13(_ text: String) -> String {
        String(text.map { character in
            guard let ascii = character.asciiValue, Character(UnicodeScalar(ascii)).isLetter else {
                return character
            }
            let base: UInt8 = ascii >= 97 ? 97 : 65
            return Character(UnicodeScalar(base + (ascii - base + 13) % 26))
        })
    }

    private func parseURL(_ text: String) throws -> String {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw ToolError.invalidInput("Invalid URL.")
        }
        var lines = [
            "scheme: \(url.scheme ?? "")",
            "host: \(url.host ?? "")",
            "port: \(url.port.map(String.init) ?? "")",
            "user: \(url.user ?? "")",
            "path: \(url.path)",
            "query: \(url.query ?? "")",
            "fragment: \(url.fragment ?? "")",
        ]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems, !items.isEmpty
        {
            lines.append("queryItems:")
            for item in items {
                lines.append("  \(item.name) = \(item.value ?? "")")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension String {
    func padLeft(to count: Int, with pad: Character) -> String {
        if self.count >= count { return self }
        return String(repeating: String(pad), count: count - self.count) + self
    }
}

enum Morse {
    private static let map: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
        "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
        "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
        "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        " ": "/",
    ]

    static func encode(_ text: String) -> String {
        text.uppercased().compactMap { map[$0] }.joined(separator: " ")
    }

    static func decode(_ text: String) throws -> String {
        let reverse = Dictionary(uniqueKeysWithValues: map.map { ($0.value, $0.key) })
        return text.split(separator: " ").map { token -> String in
            if let character = reverse[String(token)] { return String(character) }
            return "?"
        }.joined()
    }
}

enum BaseN {
    static let base32 = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
    static let base58 = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    static let base62 = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    static func encode(_ text: String, alphabet: [Character]) throws -> String {
        let bytes = [UInt8](text.utf8)
        if bytes.isEmpty { return "" }
        var digits = [0]
        for byte in bytes {
            var carry = Int(byte)
            for i in 0..<digits.count {
                carry += digits[i] << 8
                digits[i] = carry % alphabet.count
                carry /= alphabet.count
            }
            while carry > 0 {
                digits.append(carry % alphabet.count)
                carry /= alphabet.count
            }
        }
        var leading = 0
        for byte in bytes {
            if byte == 0 { leading += 1 } else { break }
        }
        let body = digits.reversed().map { alphabet[$0] }
        return String(repeating: alphabet[0], count: leading) + String(body)
    }

    static func decode(_ text: String, alphabet: [Character]) throws -> String {
        let map = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })
        var bytes = [0]
        for character in text {
            guard let value = map[character] else {
                throw ToolError.invalidInput("Invalid character \(character).")
            }
            var carry = value
            for i in 0..<bytes.count {
                carry += bytes[i] * alphabet.count
                bytes[i] = carry & 0xff
                carry >>= 8
            }
            while carry > 0 {
                bytes.append(carry & 0xff)
                carry >>= 8
            }
        }
        var leading = 0
        for character in text {
            if character == alphabet[0] { leading += 1 } else { break }
        }
        let data = Data(repeating: 0, count: leading) + Data(bytes.reversed().map(UInt8.init))
        return String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()
    }
}

enum Ascii85 {
    static func encode(_ text: String) throws -> String {
        let data = Data(text.utf8)
        var output = "<~"
        var index = 0
        while index < data.count {
            var chunk: UInt32 = 0
            let remaining = min(4, data.count - index)
            for i in 0..<remaining {
                chunk |= UInt32(data[index + i]) << (24 - i * 8)
            }
            if remaining == 4, chunk == 0 {
                output.append("z")
            } else {
                var chars = [Character](repeating: "!", count: 5)
                var value = chunk
                for i in stride(from: 4, through: 0, by: -1) {
                    chars[i] = Character(UnicodeScalar(33 + value % 85)!)
                    value /= 85
                }
                output.append(contentsOf: chars.prefix(remaining + 1))
            }
            index += 4
        }
        output += "~>"
        return output
    }

    static func decode(_ text: String) throws -> String {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("<~") { body.removeFirst(2) }
        if body.hasSuffix("~>") { body.removeLast(2) }
        body = body.replacingOccurrences(of: "z", with: "!!!!!")
        var data = Data()
        var buffer: [UInt8] = []
        for character in body where !character.isWhitespace {
            guard let ascii = character.asciiValue, ascii >= 33, ascii <= 117 else {
                throw ToolError.invalidInput("Invalid ASCII85 character.")
            }
            buffer.append(ascii - 33)
            if buffer.count == 5 {
                var value: UInt32 = 0
                for digit in buffer { value = value * 85 + UInt32(digit) }
                data.append(UInt8((value >> 24) & 0xff))
                data.append(UInt8((value >> 16) & 0xff))
                data.append(UInt8((value >> 8) & 0xff))
                data.append(UInt8(value & 0xff))
                buffer.removeAll(keepingCapacity: true)
            }
        }
        if !buffer.isEmpty {
            let count = buffer.count
            while buffer.count < 5 { buffer.append(84) }
            var value: UInt32 = 0
            for digit in buffer { value = value * 85 + UInt32(digit) }
            let bytes = [
                UInt8((value >> 24) & 0xff),
                UInt8((value >> 16) & 0xff),
                UInt8((value >> 8) & 0xff),
                UInt8(value & 0xff),
            ]
            data.append(contentsOf: bytes.prefix(count - 1))
        }
        return String(data: data, encoding: .utf8) ?? data.map { String(format: "%02x", $0) }.joined()
    }
}

enum Base91 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&()*+,./:;<=>?@[]^_`{|}~\"")

    static func encode(_ text: String) -> String {
        let data = [UInt8](text.utf8)
        var output = ""
        var b = 0
        var n = 0
        for byte in data {
            b |= Int(byte) << n
            n += 8
            if n > 13 {
                var v = b & 8191
                if v > 88 {
                    b >>= 13
                    n -= 13
                } else {
                    v = b & 16383
                    b >>= 14
                    n -= 14
                }
                output.append(alphabet[v % 91])
                output.append(alphabet[v / 91])
            }
        }
        if n > 0 {
            output.append(alphabet[b % 91])
            if n > 7 || b > 90 {
                output.append(alphabet[b / 91])
            }
        }
        return output
    }

    static func decode(_ text: String) throws -> String {
        let map = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, $0.offset) })
        var data = Data()
        var v = -1
        var b = 0
        var n = 0
        for character in text {
            guard let c = map[character] else { continue }
            if v < 0 {
                v = c
            } else {
                v += c * 91
                b |= v << n
                n += (v & 8191) > 88 ? 13 : 14
                while true {
                    data.append(UInt8(b & 255))
                    b >>= 8
                    n -= 8
                    if n <= 7 { break }
                }
                v = -1
            }
        }
        if v > -1 {
            data.append(UInt8((b | v << n) & 255))
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
