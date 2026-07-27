import CommonCrypto
import CryptoKit
import Foundation
import Security

actor CryptoTools {
    func run(_ request: ToolRequest) throws -> ToolOutput {
        try ToolLimits.guardSize(request.primary)
        switch request.toolID {
        case "crypto.sha1":
            return ToolOutput(Insecure.SHA1.hash(data: Data(request.primary.utf8)).map { String(format: "%02x", $0) }.joined())
        case "crypto.sha256":
            return ToolOutput(SHA256.hash(data: Data(request.primary.utf8)).map { String(format: "%02x", $0) }.joined())
        case "crypto.sha512":
            return ToolOutput(SHA512.hash(data: Data(request.primary.utf8)).map { String(format: "%02x", $0) }.joined())
        case "crypto.sha3":
            return ToolOutput(SHA3_256.hash(Data(request.primary.utf8)))
        case "crypto.md5":
            return ToolOutput(Insecure.MD5.hash(data: Data(request.primary.utf8)).map { String(format: "%02x", $0) }.joined())
        case "crypto.bcrypt":
            return try ToolOutput(bcrypt(request))
        case "crypto.argon2":
            return try ToolOutput(argon2(request))
        case "crypto.pbkdf2":
            return try ToolOutput(pbkdf2(request))
        case "crypto.aes":
            return try ToolOutput(aes(request))
        case "crypto.rsa":
            return try ToolOutput(rsa(request))
        case "crypto.ecc":
            return try ToolOutput(ecc(request))
        case "crypto.password":
            return ToolOutput(generatePassword(request))
        case "crypto.token":
            return ToolOutput(generateToken(request))
        case "crypto.uuid":
            return ToolOutput(generateUUIDs(request))
        case "crypto.uuidValidate":
            return ToolOutput(validateUUIDs(request.primary))
        case "crypto.uuidConvert":
            return ToolOutput(convertUUIDs(request.primary))
        case "crypto.nanoid":
            return ToolOutput(generateNanoIDs(request))
        case "crypto.ulid":
            return ToolOutput(generateULIDs(request))
        case "crypto.snowflake":
            return ToolOutput(generateSnowflakes(request))
        case "crypto.checksum":
            return ToolOutput(checksums(request.primary))
        case "crypto.fileHash":
            return try ToolOutput(fileHashes(request))
        case "crypto.signature":
            return try ToolOutput(verifySignature(request))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func bcrypt(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "hash").lowercased()
        let cost = Int(request.options["cost"] ?? "10") ?? 10
        if mode.contains("verify") {
            let hash = request.options["hash"] ?? request.secondary
            guard !hash.isEmpty else { throw ToolError.invalidInput("Provide hash in secondary input or hash option.") }
            let ok = try PasswordHashing.bcryptVerify(password: request.primary, hash: hash)
            return ok ? "Password matches hash." : "Password does not match hash."
        }
        return try PasswordHashing.bcrypt(request.primary, cost: cost)
    }

    private func argon2(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "hash").lowercased()
        if mode.contains("verify") {
            let hash = request.options["hash"] ?? request.secondary
            guard !hash.isEmpty else {
                throw ToolError.invalidInput("Provide hash in secondary input or hash option.")
            }
            let ok = try PasswordHashing.argon2idVerify(password: request.primary, hash: hash)
            return ok ? "Password matches Argon2id hash." : "Password does not match Argon2id hash."
        }
        let memory = Int(request.options["memoryKiB"] ?? "16384") ?? 16_384
        let iterations = Int(request.options["iterations"] ?? "2") ?? 2
        let parallelism = Int(request.options["parallelism"] ?? "1") ?? 1
        return try PasswordHashing.argon2id(
            request.primary,
            memoryKiB: memory,
            iterations: iterations,
            parallelism: parallelism
        )
    }

    private func pbkdf2(_ request: ToolRequest) throws -> String {
        let password = request.primary
        let salt = request.options["salt"] ?? "toolbox"
        let iterations = max(1_000, Int(request.options["iterations"] ?? "100000") ?? 100_000)
        let keyLength = min(64, max(16, Int(request.options["keyLength"] ?? "32") ?? 32))
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            password, password.utf8.count,
            salt, salt.utf8.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &derived,
            keyLength
        )
        guard status == kCCSuccess else { throw ToolError.failed("PBKDF2 failed (\(status)).") }
        return derived.map { String(format: "%02x", $0) }.joined()
    }

    private func aes(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "encrypt").lowercased()
        let passphrase = request.options["passphrase"] ?? ""
        guard !passphrase.isEmpty else { throw ToolError.invalidInput("Passphrase is required.") }
        let key = SymmetricKey(data: SHA256.hash(data: Data(passphrase.utf8)))
        if mode.contains("decrypt") {
            guard let combined = Data(base64Encoded: request.primary.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.invalidInput("Ciphertext must be Base64 (nonce + ciphertext + tag).")
            }
            let box = try AES.GCM.SealedBox(combined: combined)
            let plain = try AES.GCM.open(box, using: key)
            return String(data: plain, encoding: .utf8) ?? plain.map { String(format: "%02x", $0) }.joined()
        }
        let sealed = try AES.GCM.seal(Data(request.primary.utf8), using: key)
        guard let combined = sealed.combined else {
            throw ToolError.failed("AES-GCM seal did not produce combined output.")
        }
        return combined.base64EncodedString()
    }

    private func rsa(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "encrypt").lowercased()
        let keyPEM = request.options["key"] ?? request.secondary
        guard !keyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.invalidInput("Provide a PEM key in the key option (or secondary input).")
        }
        if mode.contains("decrypt") {
            let privateKey = try SecKeyHelpers.privateKey(fromPEM: keyPEM)
            guard let data = Data(base64Encoded: request.primary.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw ToolError.invalidInput("Ciphertext must be Base64.")
            }
            var error: Unmanaged<CFError>?
            guard let plain = SecKeyCreateDecryptedData(
                privateKey,
                .rsaEncryptionOAEPSHA256,
                data as CFData,
                &error
            ) as Data?
            else {
                throw ToolError.failed((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "RSA decrypt failed.")
            }
            return String(data: plain, encoding: .utf8) ?? plain.base64EncodedString()
        }
        let publicKey = try SecKeyHelpers.publicKey(fromPEM: keyPEM)
        var error: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            Data(request.primary.utf8) as CFData,
            &error
        ) as Data?
        else {
            throw ToolError.failed((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "RSA encrypt failed.")
        }
        return cipher.base64EncodedString()
    }

    private func ecc(_ request: ToolRequest) throws -> String {
        let mode = (request.options["mode"] ?? "sign").lowercased()
        let keyPEM = request.options["key"] ?? request.secondary
        if mode.contains("verify") {
            let publicKey = try SecKeyHelpers.publicKey(fromPEM: keyPEM)
            guard let signature = Data(base64Encoded: request.options["signature"] ?? "") else {
                throw ToolError.invalidInput("Provide Base64 signature in options.")
            }
            var error: Unmanaged<CFError>?
            let ok = SecKeyVerifySignature(
                publicKey,
                .ecdsaSignatureMessageX962SHA256,
                Data(request.primary.utf8) as CFData,
                signature as CFData,
                &error
            )
            return ok ? "Signature valid." : "Signature invalid."
        }
        let privateKey = try SecKeyHelpers.privateKey(fromPEM: keyPEM)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            Data(request.primary.utf8) as CFData,
            &error
        ) as Data?
        else {
            throw ToolError.failed((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "ECC sign failed.")
        }
        return signature.base64EncodedString()
    }

    private func generatePassword(_ request: ToolRequest) -> String {
        let length = min(128, max(8, Int(request.options["length"] ?? "20") ?? 20))
        let charsetName = (request.options["charset"] ?? "all").lowercased()
        var charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        if charsetName == "all" { charset += "!@#$%^&*()-_=+[]{}" }
        if charsetName == "alnum" { /* already */ }
        if charsetName == "alpha" { charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        let chars = Array(charset)
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    private func generateToken(_ request: ToolRequest) -> String {
        let count = min(64, max(8, Int(request.options["bytes"] ?? "32") ?? 32))
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateUUIDs(_ request: ToolRequest) -> String {
        let count = min(100, max(1, Int(request.options["count"] ?? "1") ?? 1))
        let version = (request.options["version"] ?? "4").lowercased()
        return (0..<count).map { _ in
            if version == "7" { return uuidV7() }
            return UUID().uuidString.lowercased()
        }.joined(separator: "\n")
    }

    private func uuidV7() -> String {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = UInt8((millis >> 40) & 0xff)
        bytes[1] = UInt8((millis >> 32) & 0xff)
        bytes[2] = UInt8((millis >> 24) & 0xff)
        bytes[3] = UInt8((millis >> 16) & 0xff)
        bytes[4] = UInt8((millis >> 8) & 0xff)
        bytes[5] = UInt8(millis & 0xff)
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
    }

    private func validateUUIDs(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { line in
            let value = line.trimmingCharacters(in: .whitespaces)
            return UUID(uuidString: value) == nil ? "\(value): invalid" : "\(value): valid"
        }.joined(separator: "\n")
    }

    private func convertUUIDs(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            let value = line.trimmingCharacters(in: .whitespaces)
            guard let uuid = UUID(uuidString: value) else { return "\(value): invalid" }
            return [
                uuid.uuidString.lowercased(),
                uuid.uuidString.uppercased(),
                "urn:uuid:\(uuid.uuidString.lowercased())",
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func generateNanoIDs(_ request: ToolRequest) -> String {
        let size = min(64, max(4, Int(request.options["size"] ?? "21") ?? 21))
        let count = min(100, max(1, Int(request.options["count"] ?? "1") ?? 1))
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz-")
        return (0..<count).map { _ in
            var bytes = [UInt8](repeating: 0, count: size)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return String(bytes.map { alphabet[Int($0) % alphabet.count] })
        }.joined(separator: "\n")
    }

    private func generateULIDs(_ request: ToolRequest) -> String {
        let count = min(100, max(1, Int(request.options["count"] ?? "1") ?? 1))
        return (0..<count).map { _ in ULID.generate() }.joined(separator: "\n")
    }

    private func generateSnowflakes(_ request: ToolRequest) -> String {
        let count = min(100, max(1, Int(request.options["count"] ?? "1") ?? 1))
        let worker = UInt64(request.options["workerId"] ?? "1") ?? 1
        let epoch: UInt64 = 1_288_836_000_000
        return (0..<count).map { index in
            let millis = UInt64(Date().timeIntervalSince1970 * 1000) - epoch
            let value = (millis << 22) | ((worker & 0x3ff) << 12) | UInt64(index & 0xfff)
            return String(value)
        }.joined(separator: "\n")
    }

    private func checksums(_ text: String) -> String {
        let data = Data(text.utf8)
        return [
            "crc32: \(String(format: "%08x", CRC32.checksum(data)))",
            "adler32: \(String(format: "%08x", Adler32.checksum(data)))",
            "bytes: \(data.count)",
        ].joined(separator: "\n")
    }

    private func fileHashes(_ request: ToolRequest) throws -> String {
        let filePath = (request.options["filePath"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let data: Data
        let source: String
        if !filePath.isEmpty {
            let url = URL(fileURLWithPath: filePath)
            guard FileManager.default.isReadableFile(atPath: filePath) else {
                throw ToolError.invalidInput("Cannot read file at filePath.")
            }
            data = try Data(contentsOf: url)
            source = url.lastPathComponent
        } else {
            data = Data(request.primary.utf8)
            source = "editor text (\(data.count) bytes)"
        }
        let algorithm = (request.options["algorithm"] ?? "all").lowercased()
        var lines: [String] = ["source: \(source)", "bytes: \(data.count)"]
        if algorithm == "all" || algorithm == "md5" {
            lines.append("md5: \(Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined())")
        }
        if algorithm == "all" || algorithm == "sha1" {
            lines.append("sha1: \(Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined())")
        }
        if algorithm == "all" || algorithm == "sha256" {
            lines.append("sha256: \(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())")
        }
        if algorithm == "all" || algorithm == "sha512" {
            lines.append("sha512: \(SHA512.hash(data: data).map { String(format: "%02x", $0) }.joined())")
        }
        return lines.joined(separator: "\n")
    }

    private func verifySignature(_ request: ToolRequest) throws -> String {
        let algorithm = (request.options["algorithm"] ?? "ecdsa").lowercased()
        let keyPEM = request.options["key"] ?? request.secondary
        guard let signature = Data(base64Encoded: request.options["signature"] ?? "") else {
            throw ToolError.invalidInput("Provide Base64 signature in options.")
        }
        let publicKey = try SecKeyHelpers.publicKey(fromPEM: keyPEM)
        let algorithmID: SecKeyAlgorithm = algorithm.contains("rsa")
            ? .rsaSignatureMessagePKCS1v15SHA256
            : .ecdsaSignatureMessageX962SHA256
        var error: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(
            publicKey,
            algorithmID,
            Data(request.primary.utf8) as CFData,
            signature as CFData,
            &error
        )
        return ok ? "Signature valid." : "Signature invalid."
    }
}

enum SHA3_256 {
    // Keccak-f[1600] SHA3-256 (FIPS 202)
    static func hash(_ data: Data) -> String {
        var state = [[UInt64]](repeating: [UInt64](repeating: 0, count: 5), count: 5)
        let rate = 136
        var offset = 0
        var block = [UInt8](repeating: 0, count: rate)
        while offset < data.count {
            let take = min(rate, data.count - offset)
            for i in 0..<take { block[i] = data[offset + i] }
            for i in take..<rate { block[i] = 0 }
            if take < rate {
                block[take] ^= 0x06
                block[rate - 1] ^= 0x80
                absorb(block, into: &state)
                break
            }
            absorb(block, into: &state)
            offset += take
            if offset == data.count {
                block = [UInt8](repeating: 0, count: rate)
                block[0] ^= 0x06
                block[rate - 1] ^= 0x80
                absorb(block, into: &state)
            }
        }
        if data.isEmpty {
            block[0] ^= 0x06
            block[rate - 1] ^= 0x80
            absorb(block, into: &state)
        }
        var out = [UInt8]()
        while out.count < 32 {
            for y in 0..<5 {
                for x in 0..<5 {
                    var lane = state[x][y]
                    for _ in 0..<8 {
                        out.append(UInt8(lane & 0xff))
                        lane >>= 8
                        if out.count == 32 { break }
                    }
                    if out.count == 32 { break }
                }
                if out.count == 32 { break }
            }
        }
        return out.prefix(32).map { String(format: "%02x", $0) }.joined()
    }

    private static func absorb(_ block: [UInt8], into state: inout [[UInt64]]) {
        for i in stride(from: 0, to: block.count, by: 8) {
            var lane: UInt64 = 0
            for b in 0..<8 { lane |= UInt64(block[i + b]) << (8 * b) }
            let x = (i / 8) % 5
            let y = (i / 8) / 5
            state[x][y] ^= lane
        }
        keccakF(&state)
    }

    private static let rotc: [Int] = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14,
    ]
    private static let piln: [Int] = [
        0, 10, 20, 5, 15, 16, 7, 23, 2, 11, 22, 14, 3, 9, 13, 17, 24, 4, 12, 18, 19, 21, 8, 6, 1,
    ]
    private static let rc: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]

    private static func keccakF(_ state: inout [[UInt64]]) {
        for round in 0..<24 {
            var c = [UInt64](repeating: 0, count: 5)
            for x in 0..<5 {
                c[x] = state[x][0] ^ state[x][1] ^ state[x][2] ^ state[x][3] ^ state[x][4]
            }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotate(c[(x + 1) % 5], 1)
                for y in 0..<5 { state[x][y] ^= d }
            }
            var flat = [UInt64](repeating: 0, count: 25)
            for y in 0..<5 {
                for x in 0..<5 { flat[x + 5 * y] = state[x][y] }
            }
            var t = flat[1]
            for i in 0..<24 {
                let j = piln[i + 1]
                let temp = flat[j]
                flat[j] = rotate(t, rotc[i + 1])
                t = temp
            }
            for y in 0..<5 {
                for x in 0..<5 { state[x][y] = flat[x + 5 * y] }
            }
            for y in 0..<5 {
                let row = (0..<5).map { state[$0][y] }
                for x in 0..<5 {
                    state[x][y] = row[x] ^ ((~row[(x + 1) % 5]) & row[(x + 2) % 5])
                }
            }
            state[0][0] ^= rc[round]
        }
    }

    private static func rotate(_ value: UInt64, _ n: Int) -> UInt64 {
        (value << n) | (value >> (64 - n))
    }
}

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xedb88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }
}

enum Adler32 {
    static func checksum(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }
}

enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func generate() -> String {
        var time = UInt64(Date().timeIntervalSince1970 * 1000)
        var chars = [Character](repeating: "0", count: 26)
        for i in stride(from: 9, through: 0, by: -1) {
            chars[i] = alphabet[Int(time % 32)]
            time /= 32
        }
        var random = [UInt8](repeating: 0, count: 10)
        _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
        var value = random.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        for i in stride(from: 25, through: 10, by: -1) {
            chars[i] = alphabet[Int(value % 32)]
            value /= 32
        }
        return String(chars)
    }
}

enum SecKeyHelpers {
    static func publicKey(fromPEM pem: String) throws -> SecKey {
        try key(fromPEM: pem, isPublic: true)
    }

    static func privateKey(fromPEM pem: String) throws -> SecKey {
        try key(fromPEM: pem, isPublic: false)
    }

    private static func key(fromPEM pem: String, isPublic: Bool) throws -> SecKey {
        let cleaned = pem
            .components(separatedBy: .newlines)
            .filter { !$0.contains("BEGIN") && !$0.contains("END") }
            .joined()
        guard let data = Data(base64Encoded: cleaned) else {
            throw ToolError.invalidInput("Invalid PEM key.")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: pem.contains("EC") ? kSecAttrKeyTypeECSECPrimeRandom : kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: isPublic ? kSecAttrKeyClassPublic : kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw ToolError.failed((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "Could not create key.")
        }
        return key
    }
}
