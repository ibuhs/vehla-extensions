import Foundation

enum VIAError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
enum VIAProtocol {
    static let supportedVersion = 12
    // No reset, raw EEPROM, macro-write or firmware-update commands.
    static let commands: Set<UInt8> = [0x01, 0x04, 0x05, 0x0c, 0x0d, 0x0e, 0x11, 0x12]
    static func packet(_ command: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count <= 31)
        return [command] + payload + Array(repeating: 0, count: 31 - payload.count)
    }
    static func matches(_ response: [UInt8], request: [UInt8]) -> Bool {
        guard response.count == 32, request.count == 32, response[0] == request[0], commands.contains(request[0]) else { return false }
        switch request[0] {
        case 0x04: return response.prefix(4) == request.prefix(4)
        case 0x05: return response.prefix(6) == request.prefix(6)
        case 0x0e, 0x12: return response.prefix(4) == request.prefix(4)
        default: return true
        }
    }
    static func bufferRequest(command: UInt8, offset: Int, length: Int) -> [UInt8] {
        precondition([0x0e, 0x12].contains(command) && (0...65535).contains(offset) && (1...28).contains(length))
        return packet(command, [UInt8(offset >> 8), UInt8(offset & 255), UInt8(length)])
    }
    static func setKey(_ code: UInt16, layer: Int, row: Int, column: Int, profile: QMKKeyboardProfile) throws -> [UInt8] {
        guard (0..<profile.layers).contains(layer), (0..<profile.rows).contains(row), (0..<profile.columns).contains(column) else {
            throw VIAError.message("The key is outside this keyboard's matrix.")
        }
        return packet(0x05, [UInt8(layer), UInt8(row), UInt8(column), UInt8(code >> 8), UInt8(code & 255)])
    }
    static func keycodes(_ bytes: [UInt8], count: Int) throws -> [UInt16] {
        guard bytes.count == count * 2 else { throw VIAError.message("Incomplete keymap reply. No changes were made.") }
        return stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
    }
}

@MainActor protocol VIAEndpoint: AnyObject {
    var keymapProfile: QMKKeyboardProfile? { get }
    var keymapIdentity: String { get }
    func beginKeymapSession() async throws
    func endKeymapSession()
    func exchangeVIA(_ packet: [UInt8]) async throws -> [UInt8]
}
