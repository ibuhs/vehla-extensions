import XCTest
@testable import PeripheralMatrix

final class KeyboardCatalogTests: XCTestCase {
    func testPinnedProfilesUseTheirOwnMatrixStrideAndUniqueUSBIdentity() throws {
        XCTAssertEqual(QMKKeyboardCatalog.entries.count, 14)
        XCTAssertEqual(Set(QMKKeyboardCatalog.entries.map { "\($0.vendor):\($0.product)" }).count, 14)
        for entry in QMKKeyboardCatalog.entries {
            let profile = entry.profile
            XCTAssertEqual(profile.layers, 4)
            XCTAssertEqual(Set(profile.keys.map(\.id)).count, profile.keys.count)
            XCTAssertTrue(profile.keys.allSatisfy { $0.id == $0.row * profile.columns + $0.column && $0.row < profile.rows && $0.column < profile.columns })
            XCTAssertTrue(profile.keys.allSatisfy { $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0 })
            XCTAssertEqual(entry.sha256.count, 64)
            XCTAssertTrue(entry.source.contains("raw.githubusercontent.com"))
            XCTAssertEqual(QMKKeyboardCatalog.profile(vendor: entry.vendor, product: entry.product), profile)
        }
        XCTAssertNil(QMKKeyboardCatalog.profile(vendor: 0x3434, product: 0xffff))
        XCTAssertNil(QMKKeyboardCatalog.profile(vendor: 0x1234, product: 0x0810))
    }
    @MainActor func testQ1MaxAndV4WritesUseCorrectMatrixCoordinates() async throws {
        for product: UInt32 in [0x0810, 0x0340] {
            let profile = try XCTUnwrap(QMKKeyboardCatalog.profile(vendor: 0x3434, product: product))
            let device = MockVIAEndpoint(profile: profile)
            let session = VIAKeymapSession(endpoint: device, profile: profile)
            let baseline = try await session.load()
            let key = try XCTUnwrap(profile.keys.last)
            let index = 3 * profile.keysPerLayer + key.id
            var draft = baseline.keycodes; draft[index] = 0x0806
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qmk-catalog-\(UUID())")
            defer { try? FileManager.default.removeItem(at: directory) }
            let (saved, _) = try await session.apply(baseline: baseline, draft: draft, backupDirectory: directory)
            XCTAssertEqual(saved.keycodes, draft)
            XCTAssertEqual(saved.macroBytes, baseline.macroBytes)
            XCTAssertEqual(device.writes, 1)
        }
    }
    func testQ1MaxVariantsAndCommonSizesHaveVerifiedKeyCounts() throws {
        for (product, count) in [(0x0810, 82), (0x0811, 83), (0x0812, 86), (0x0340, 61), (0x0320, 67), (0x0310, 82), (0x0330, 87), (0x0350, 100), (0x0360, 108)] {
            let profile = try XCTUnwrap(QMKKeyboardCatalog.profile(vendor: 0x3434, product: UInt32(product)))
            XCTAssertEqual(profile.keys.count, count, profile.name)
        }
        let q1 = try XCTUnwrap(QMKKeyboardCatalog.profile(vendor: 0x3434, product: 0x0810))
        XCTAssertEqual(QMKKeycodes.label(0x7e00, profile: q1), "Left Option")
        XCTAssertEqual(QMKKeycodes.label(0x7e0f, profile: q1), "Battery Level")
        XCTAssertEqual(QMKKeycodes.label(0x7e00, profile: .k10ProANSIWhite), "Mission Control")
    }
}
