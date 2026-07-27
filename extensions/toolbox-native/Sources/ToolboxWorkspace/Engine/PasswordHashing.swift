import BCryptSwift
import CArgon2
import Foundation
import Security

enum PasswordHashing {
    static func bcrypt(_ password: String, cost: Int = 10) throws -> String {
        let rounds = UInt(min(15, max(4, cost)))
        let salt = BCryptSwift.generateSaltWithNumberOfRounds(rounds)
        do {
            return try BCryptSwiftModern.hashPassword(password, withSalt: salt)
        } catch {
            throw ToolError.failed("Bcrypt hashing failed: \(error.localizedDescription)")
        }
    }

    static func bcryptVerify(password: String, hash: String) throws -> Bool {
        do {
            return try BCryptSwiftModern.verifyPassword(password, matchesHash: hash)
        } catch {
            throw ToolError.invalidInput("Not a valid bcrypt hash, or verification failed.")
        }
    }

    /// RFC 9106 Argon2id via the PHC reference C implementation (PHC encoded string).
    static func argon2id(
        _ password: String,
        memoryKiB: Int = 16_384,
        iterations: Int = 2,
        parallelism: Int = 1,
        hashLength: Int = 32
    ) throws -> String {
        let m = UInt32(min(64_000, max(8, memoryKiB)))
        let t = UInt32(min(10, max(1, iterations)))
        let p = UInt32(min(4, max(1, parallelism)))
        let length = min(64, max(16, hashLength))
        var salt = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt) == errSecSuccess else {
            throw ToolError.failed("Could not generate salt.")
        }
        let passwordBytes = Array(password.utf8)
        let encodedLen = argon2_encodedlen(t, m, p, UInt32(salt.count), UInt32(length), Argon2_id)
        var encoded = [Int8](repeating: 0, count: encodedLen)
        let code = passwordBytes.withUnsafeBufferPointer { pwdPtr in
            salt.withUnsafeBufferPointer { saltPtr in
                argon2_hash(
                    t,
                    m,
                    p,
                    pwdPtr.baseAddress,
                    passwordBytes.count,
                    saltPtr.baseAddress,
                    salt.count,
                    nil,
                    length,
                    &encoded,
                    encodedLen,
                    Argon2_id,
                    UInt32(ARGON2_VERSION_13.rawValue)
                )
            }
        }
        guard code == ARGON2_OK.rawValue else {
            let message = String(cString: argon2_error_message(code))
            throw ToolError.failed("Argon2id hashing failed: \(message)")
        }
        return String(decoding: encoded.map { UInt8(bitPattern: $0) }.prefix { $0 != 0 }, as: UTF8.self)
    }

    static func argon2idVerify(password: String, hash: String) throws -> Bool {
        let passwordBytes = Array(password.utf8)
        let code = passwordBytes.withUnsafeBufferPointer { pwdPtr in
            hash.withCString { encoded in
                argon2id_verify(encoded, pwdPtr.baseAddress, passwordBytes.count)
            }
        }
        if code == ARGON2_OK.rawValue { return true }
        if code == ARGON2_VERIFY_MISMATCH.rawValue { return false }
        let message = String(cString: argon2_error_message(code))
        throw ToolError.invalidInput("Not a valid Argon2id hash: \(message)")
    }
}
