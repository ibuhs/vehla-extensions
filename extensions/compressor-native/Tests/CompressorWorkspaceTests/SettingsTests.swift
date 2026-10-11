import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

@MainActor
final class SettingsTests: XCTestCase {
    private func makeModel(in directory: URL) -> CompressorModel {
        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(
            packageID: "x", workspaceID: "compressor", dataDirectory: directory,
            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
            secretLookup: { _ in nil }, actionHandler: { _ in })
        return CompressorModel(context: context)
    }

    func testPlainIsTheDefaultAndChoiceIsRemembered() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = makeModel(in: directory)
        XCTAssertFalse(first.tinted, "plain Liquid Glass must be the default")

        first.toggleTint()
        XCTAssertTrue(first.tinted)
        XCTAssertTrue(makeModel(in: directory).tinted, "choice should survive a relaunch")

        first.toggleTint()
        XCTAssertFalse(makeModel(in: directory).tinted)
    }

    func testQualityDefaultsToBalancedAndIsRemembered() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quality-settings-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = makeModel(in: directory)
        XCTAssertEqual(first.quality, .balanced)
        first.setQuality(.best)
        XCTAssertEqual(makeModel(in: directory).quality, .best)
        first.setTinted(true) // saving one setting must not wipe another
        let again = makeModel(in: directory)
        XCTAssertEqual(again.quality, .best)
        XCTAssertTrue(again.tinted)
    }
}
