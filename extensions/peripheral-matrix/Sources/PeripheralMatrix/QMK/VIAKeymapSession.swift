import Foundation

struct VIAKeymapBackup: Codable, Equatable, Sendable {
    let formatVersion: Int
    let profileID: String
    let deviceIdentity: String
    let protocolVersion: Int
    let rows: Int
    let columns: Int
    let layers: Int
    let captured: Date
    let keycodes: [UInt16]
    let macroCount: Int
    let macroBytes: Data
}
struct QMKKeyChange: Identifiable, Equatable, Sendable {
    let index: Int
    let before: UInt16
    let after: UInt16
    var id: Int { index }
}

@MainActor final class VIAKeymapSession {
    let endpoint: any VIAEndpoint
    let profile: QMKKeyboardProfile
    init(endpoint: any VIAEndpoint, profile: QMKKeyboardProfile) { self.endpoint = endpoint; self.profile = profile }
    func load() async throws -> VIAKeymapBackup {
        try await endpoint.beginKeymapSession(); defer { endpoint.endKeymapSession() }
        return try await readCoherentSnapshot()
    }
    private func exchange(_ packet: [UInt8]) async throws -> [UInt8] {
        let response = try await endpoint.exchangeVIA(packet)
        guard VIAProtocol.matches(response, request: packet) else { throw VIAError.message("Mismatched VIA reply. Reload the keyboard.") }
        return response
    }
    private func readBuffer(_ command: UInt8, count: Int) async throws -> [UInt8] {
        var bytes: [UInt8] = []
        for offset in stride(from: 0, to: count, by: 28) {
            let length = min(28, count - offset)
            let response = try await exchange(VIAProtocol.bufferRequest(command: command, offset: offset, length: length))
            bytes.append(contentsOf: response[4..<(4 + length)])
        }
        return bytes
    }
    private func readCoherentSnapshot() async throws -> VIAKeymapBackup {
        guard endpoint.keymapProfile == profile else { throw VIAError.message("Keyboard geometry does not match the supported profile.") }
        let version = try await exchange(VIAProtocol.packet(0x01))
        let protocolVersion = Int(version[1]) << 8 | Int(version[2])
        guard protocolVersion == VIAProtocol.supportedVersion else { throw VIAError.message("This editor requires verified VIA protocol 12; this device reports \(protocolVersion).") }
        let layerReply = try await exchange(VIAProtocol.packet(0x11))
        guard Int(layerReply[1]) == profile.layers else { throw VIAError.message("Firmware layer count differs from the supported profile. No changes were made.") }
        let keymap = try await readBuffer(0x12, count: profile.totalKeys * 2)
        let macroCount = Int(try await exchange(VIAProtocol.packet(0x0c))[1])
        let macroSizeReply = try await exchange(VIAProtocol.packet(0x0d))
        let macroSize = Int(macroSizeReply[1]) << 8 | Int(macroSizeReply[2])
        guard macroSize <= 8192, macroCount <= 128 else { throw VIAError.message("Unsupported macro storage size.") }
        let macros = try await readBuffer(0x0e, count: macroSize)
        // A VIA/Launcher edit from another process must not become our baseline.
        let checkedKeymap = try await readBuffer(0x12, count: keymap.count)
        let checkedMacros = try await readBuffer(0x0e, count: macros.count)
        guard checkedKeymap == keymap, checkedMacros == macros else { throw VIAError.message("The keyboard changed during loading. Close VIA/Launcher and reload.") }
        return VIAKeymapBackup(formatVersion: 1, profileID: profile.id, deviceIdentity: endpoint.keymapIdentity,
            protocolVersion: protocolVersion, rows: profile.rows, columns: profile.columns, layers: profile.layers,
            captured: Date(), keycodes: try VIAProtocol.keycodes(keymap, count: profile.totalKeys), macroCount: macroCount, macroBytes: Data(macros))
    }
    static func changes(from baseline: [UInt16], to draft: [UInt16]) throws -> [QMKKeyChange] {
        guard baseline.count == draft.count else { throw VIAError.message("The draft has the wrong number of keys.") }
        return baseline.indices.compactMap { baseline[$0] == draft[$0] ? nil : QMKKeyChange(index: $0, before: baseline[$0], after: draft[$0]) }
    }
    func apply(baseline: VIAKeymapBackup, draft: [UInt16], backupDirectory: URL) async throws -> (VIAKeymapBackup, URL) {
        guard baseline.profileID == profile.id, baseline.deviceIdentity == endpoint.keymapIdentity,
              draft.count == profile.totalKeys else { throw VIAError.message("Reload this keyboard before applying changes.") }
        let changes = try Self.changes(from: baseline.keycodes, to: draft)
        guard !changes.isEmpty else { throw VIAError.message("No changes to apply.") }
        let positions = Set(profile.keys.map(\.id))
        guard changes.allSatisfy({ positions.contains($0.index % profile.keysPerLayer) }) else { throw VIAError.message("Unused matrix positions cannot be programmed.") }
        for change in changes { try QMKKeycodes.validate(change.after, layerCount: profile.layers, macroCount: baseline.macroCount) }
        try await endpoint.beginKeymapSession(); defer { endpoint.endKeymapSession() }
        let fresh = try await readCoherentSnapshot()
        guard fresh.keycodes == baseline.keycodes else { throw VIAError.message("The keyboard mapping changed after you loaded it. Reload before applying your draft.") }
        for change in changes { try QMKKeycodes.validate(change.after, layerCount: profile.layers, macroCount: fresh.macroCount) }
        let backup = try await saveBackup(fresh, in: backupDirectory)
        var attempted: [QMKKeyChange] = []
        do {
            for change in changes {
                attempted.append(change) // Even a timed-out write may have reached EEPROM.
                try await write(change.after, at: change.index)
            }
            let result = try await readCoherentSnapshot()
            guard result.keycodes == draft, result.macroBytes == fresh.macroBytes, result.macroCount == fresh.macroCount else {
                throw VIAError.message("Keyboard verification failed.")
            }
            return (result, backup)
        } catch {
            // Restore only keys we attempted, not unrelated keys or macro buffers.
            var rollbackSucceeded = true
            for change in attempted.reversed() {
                do { try await write(change.before, at: change.index) } catch { rollbackSucceeded = false }
            }
            throw VIAError.message(rollbackSucceeded ? "Apply failed; attempted keys were restored. Backup: \(backup.lastPathComponent). Reload the keyboard."
                : "Apply was interrupted and some keys may have changed. Reconnect, reload, and restore from backup: \(backup.lastPathComponent).")
        }
    }
    private func write(_ code: UInt16, at index: Int) async throws {
        let layer = index / profile.keysPerLayer
        let position = index % profile.keysPerLayer
        _ = try await exchange(VIAProtocol.setKey(code, layer: layer, row: position / profile.columns, column: position % profile.columns, profile: profile))
        let reply = try await exchange(VIAProtocol.packet(0x04, [UInt8(layer), UInt8(position / profile.columns), UInt8(position % profile.columns)]))
        guard UInt16(reply[4]) << 8 | UInt16(reply[5]) == code else { throw VIAError.message("The keyboard did not save this key assignment.") }
    }
    private func saveBackup(_ backup: VIAKeymapBackup, in directory: URL) async throws -> URL {
        let data = try JSONEncoder().encode(backup)
        return try await Task.detached(priority: .utility) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let destination = directory.appendingPathComponent("keymap-\(UUID().uuidString).json")
            try data.write(to: destination, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            return destination
        }.value
    }
}
