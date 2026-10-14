import XCTest
@testable import PeripheralMatrix

@MainActor final class MockVIAEndpoint: VIAEndpoint {
    var keymapProfile: QMKKeyboardProfile? = .k10ProANSIWhite
    var keymapIdentity = "test-keyboard"
    var version = 12
    var layerCount = 4
    var codes = [UInt16](repeating: 0, count: 504)
    var macros = Data([1, 2, 3, 0])
    var macroCount: UInt8 = 16
    var writes = 0
    var requests: [UInt8] = []
    var active = false
    var failWrite: Int?
    var mismatchReadbackOnce = false
    var driftDuringLoad = false
    var mutateMacrosOnWrite = false
    private var keymapPasses = 0
    init(profile: QMKKeyboardProfile = .k10ProANSIWhite) {
        keymapProfile = profile
        codes = [UInt16](repeating: 0, count: profile.totalKeys)
        for layer in 0..<profile.layers {
            for key in profile.keys { codes[layer * profile.keysPerLayer + key.id] = UInt16(4 + key.id % 26) }
        }
    }
    func beginKeymapSession() async throws {
        guard !active else { throw VIAError.message("Overlapping test session") }
        active = true
    }
    func endKeymapSession() { active = false }
    func exchangeVIA(_ packet: [UInt8]) async throws -> [UInt8] {
        XCTAssertTrue(active)
        var response = packet; requests.append(packet[0])
        switch packet[0] {
        case 0x01: response[1] = UInt8(version >> 8); response[2] = UInt8(version & 255)
        case 0x11: response[1] = UInt8(layerCount)
        case 0x0c: response[1] = macroCount
        case 0x0d: response[1] = UInt8(macros.count >> 8); response[2] = UInt8(macros.count & 255)
        case 0x12, 0x0e:
            let offset = Int(packet[1]) << 8 | Int(packet[2]), length = Int(packet[3])
            if packet[0] == 0x12 && offset == 0 {
                keymapPasses += 1
                if driftDuringLoad && keymapPasses == 2 { codes[0] = 0x09 }
            }
            let bytes = packet[0] == 0x12 ? codes.flatMap { [UInt8($0 >> 8), UInt8($0 & 255)] } : Array(macros)
            guard offset + length <= bytes.count else { throw VIAError.message("Read outside fake storage") }
            response.replaceSubrange(4..<(4 + length), with: bytes[offset..<(offset + length)])
        case 0x04, 0x05:
            let profile = try XCTUnwrap(keymapProfile)
            let index = Int(packet[1]) * profile.keysPerLayer + Int(packet[2]) * profile.columns + Int(packet[3])
            guard codes.indices.contains(index) else { throw VIAError.message("Write outside fake matrix") }
            if packet[0] == 0x05 {
                writes += 1; codes[index] = UInt16(packet[4]) << 8 | UInt16(packet[5])
                if mutateMacrosOnWrite { macros[0] = 9 }
                if failWrite == writes { throw VIAError.message("Simulated lost acknowledgement") }
            } else {
                let code = mismatchReadbackOnce ? UInt16(0xffff) : codes[index]
                mismatchReadbackOnce = false
                response[4] = UInt8(code >> 8); response[5] = UInt8(code & 255)
            }
        default: throw VIAError.message("Unexpected command")
        }
        return response
    }
}

final class VIAKeymapTests: XCTestCase {
    func testProtocolMatchesCoordinatesAndWriteValue() throws {
        let profile = QMKKeyboardProfile.k10ProANSIWhite
        let packet = try VIAProtocol.setKey(0x0806, layer: 2, row: 3, column: 4, profile: profile)
        XCTAssertEqual(Array(packet.prefix(6)), [5, 2, 3, 4, 8, 6])
        XCTAssertTrue(VIAProtocol.matches(packet, request: packet))
        var wrong = packet; wrong[3] = 5
        XCTAssertFalse(VIAProtocol.matches(wrong, request: packet))
        wrong = packet; wrong[5] = 7
        XCTAssertFalse(VIAProtocol.matches(wrong, request: packet))
        XCTAssertFalse(VIAProtocol.matches(LayerProtocol.query(), request: packet))
        XCTAssertThrowsError(try VIAProtocol.setKey(4, layer: 4, row: 0, column: 0, profile: profile))
        XCTAssertFalse(VIAProtocol.commands.contains(0x06))
        XCTAssertFalse(VIAProtocol.commands.contains(0x0f))
        XCTAssertFalse(VIAProtocol.commands.contains(0x13))
    }
    func testKeycodesAndLayerRangeValidation() throws {
        XCTAssertEqual(QMKKeycodes.parse("KC_A"), 4)
        XCTAssertEqual(QMKKeycodes.parse("KC_TRNS"), 1)
        XCTAssertEqual(QMKKeycodes.parse("MO(1)"), 0x5221)
        XCTAssertEqual(QMKKeycodes.parse("0x0806"), 0x0806)
        XCTAssertNil(QMKKeycodes.parse("0x10000"))
        XCTAssertEqual(QMKKeycodes.shortcut(6, modifiers: 8), 0x0806)
        XCTAssertEqual(QMKKeycodes.label(0x0806), "⌘C")
        XCTAssertEqual(QMKKeycodes.layerAction("TG", layer: 3, count: 4), 0x5263)
        XCTAssertThrowsError(try QMKKeycodes.validate(0x5224, layerCount: 4))
        XCTAssertThrowsError(try QMKKeycodes.validate(0x4406, layerCount: 4))
        let profile = QMKKeyboardProfile.k10ProANSIWhite
        XCTAssertEqual(profile.keys.count, 108)
        XCTAssertEqual(Set(profile.keys.map(\.id)).count, 108)
        XCTAssertTrue(profile.keys.allSatisfy { $0.row < profile.rows && $0.column < profile.columns })
    }
    @MainActor func testLoadIsReadOnlyAndCapturesAllLayersAndMacros() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let snapshot = try await session.load()
        XCTAssertEqual(snapshot.keycodes, device.codes); XCTAssertEqual(snapshot.macroBytes, device.macros)
        XCTAssertEqual(snapshot.keycodes.count, 504); XCTAssertEqual(snapshot.layers, 4)
        XCTAssertEqual(device.writes, 0); XCTAssertFalse(device.active)
    }
    @MainActor func testApplyWritesOnlyDiffBacksUpAndPreservesMacros() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let baseline = try await session.load(); var draft = baseline.keycodes
        draft[0] = 0x0806; draft[126 + 1] = 0x5221
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        let (saved, url) = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory)
        XCTAssertEqual(device.writes, 2); XCTAssertEqual(saved.keycodes, draft)
        XCTAssertEqual(device.macros, baseline.macroBytes)
        let backup = try JSONDecoder().decode(VIAKeymapBackup.self, from: Data(contentsOf: url))
        XCTAssertEqual(backup.keycodes, baseline.keycodes); XCTAssertEqual(backup.macroBytes, baseline.macroBytes)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    @MainActor func testStaleMappingAndMissingBackupPreventEveryWrite() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let baseline = try await session.load(); var draft = baseline.keycodes; draft[0] = 0x08
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        device.codes[1] = 0x10
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Stale mapping accepted") } catch {}
        XCTAssertEqual(device.writes, 0)
        device.codes = baseline.keycodes
        try Data([0]).write(to: directory)
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Missing backup accepted") } catch {}
        XCTAssertEqual(device.writes, 0)
    }
    @MainActor func testLostAcknowledgementRestoresAttemptedKeys() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let baseline = try await session.load(); var draft = baseline.keycodes; draft[0] = 0x08; draft[1] = 0x09
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        device.failWrite = 2
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Expected failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("restored")) }
        XCTAssertEqual(device.codes, baseline.keycodes); XCTAssertEqual(device.macros, baseline.macroBytes)
        XCTAssertEqual(device.writes, 4)
    }
    @MainActor func testReadbackMismatchRestoresAttemptedKey() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let baseline = try await session.load(); var draft = baseline.keycodes; draft[0] = 0x08
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        device.mismatchReadbackOnce = true
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Readback mismatch accepted") } catch {}
        XCTAssertEqual(device.codes, baseline.keycodes); XCTAssertEqual(device.writes, 2)
    }
    @MainActor func testUnsupportedProtocolAndChangingLoadRemainReadOnly() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        device.version = 13
        do { _ = try await session.load(); XCTFail("Unknown protocol accepted") } catch {}
        device.version = 12; device.driftDuringLoad = true
        do { _ = try await session.load(); XCTFail("Changing keymap accepted") } catch {}
        XCTAssertEqual(device.writes, 0)
    }
    @MainActor func testMacroDriftIsDetectedAndUnusedPositionsCannotBeWritten() async throws {
        let device = MockVIAEndpoint(); let session = VIAKeymapSession(endpoint: device, profile: .k10ProANSIWhite)
        let baseline = try await session.load(); var draft = baseline.keycodes
        let directory = temporaryDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
        draft[13] = 4
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Unused position accepted") } catch {}
        XCTAssertEqual(device.writes, 0)
        draft = baseline.keycodes; draft[0] = 8; device.mutateMacrosOnWrite = true
        do { _ = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory); XCTFail("Macro drift accepted") } catch {}
        XCTAssertEqual(device.codes, baseline.keycodes)
        XCTAssertFalse(device.requests.contains(0x0f))
    }
    @MainActor func testEditorDraftLayerCopyImportAndRestoreNeedExplicitApply() async throws {
        let device = MockVIAEndpoint(); let editor = QMKEditorModel(); let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        editor.load(endpoint: device, directory: directory); await editor.waitForOperation()
        let baseline = try XCTUnwrap(editor.baseline)
        editor.selectedLayer = 1; editor.selectedKey = 0; editor.assign(0x0806)
        XCTAssertEqual(editor.code(for: 0), 0x0806); XCTAssertEqual(device.writes, 0); XCTAssertTrue(editor.canApply)
        editor.discard(); XCTAssertFalse(editor.canApply)
        editor.copyLayer(from: 0); XCTAssertEqual(device.writes, 0)
        let foreign = QMKLayerPreset(formatVersion: 1, profileID: "different-board", rows: 6, columns: 21, name: "Bad", keycodes: Array(repeating: 4, count: 126))
        XCTAssertThrowsError(try editor.importLayer(data: JSONEncoder().encode(foreign)))
        let preset = QMKLayerPreset(formatVersion: 1, profileID: baseline.profileID, rows: 6, columns: 21, name: "IDE", keycodes: Array(repeating: 0x0806, count: 126))
        try editor.importLayer(data: JSONEncoder().encode(preset))
        XCTAssertEqual(editor.code(for: 0), 0x0806); XCTAssertEqual(device.writes, 0)
        let unused = 13 // Row 0 column 13 is not a physical key.
        XCTAssertEqual(editor.draft[126 + unused], baseline.keycodes[126 + unused])
        try editor.restoreBackup(data: JSONEncoder().encode(baseline))
        XCTAssertEqual(editor.draft, baseline.keycodes); XCTAssertEqual(device.writes, 0)
    }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("vehla-qmk-test-\(UUID())") }
}
