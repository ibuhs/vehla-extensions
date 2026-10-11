import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

@MainActor
final class DependenciesTests: XCTestCase {
    private let everything: (String) -> String? = { "/opt/homebrew/bin/\($0)" }
    private func without(_ names: String...) -> (String) -> String? {
        { names.contains($0) ? nil : "/opt/homebrew/bin/\($0)" }
    }

    func testNothingIsMissingWhenEverythingIsInstalled() {
        XCTAssertTrue(Dependencies.missing(optional: false, finder: everything).isEmpty)
        XCTAssertTrue(Dependencies.missing(optional: true, finder: everything).isEmpty)
        XCTAssertTrue(Dependencies.homebrewInstalled(finder: everything))
    }

    func testMissingToolIsReportedByItsHomebrewFormula() {
        let missing = Dependencies.missing(finder: without("gs", "cwebp"))
        XCTAssertEqual(missing.map(\.formula), ["ghostscript", "webp"])
    }

    func testFfmpegCountsAsMissingIfOnlyFfprobeIsGone() {
        // ffprobe ships with the ffmpeg formula, and audio detection depends on it.
        XCTAssertEqual(Dependencies.missing(finder: without("ffprobe")).map(\.formula), ["ffmpeg"])
    }

    func testOptionalToolsAreSeparateFromRequiredOnes() {
        XCTAssertTrue(Dependencies.missing(optional: false, finder: without("oxipng")).isEmpty)
        XCTAssertEqual(Dependencies.missing(optional: true, finder: without("oxipng")).map(\.formula), ["oxipng"])
    }

    func testInstallCommandListsEachFormulaOnce() {
        let missing = Dependencies.missing(finder: without("ffmpeg", "gs", "cwebp"))
        XCTAssertEqual(Dependencies.installCommand(missing), "brew install ffmpeg ghostscript webp")
    }

    func testSummaryExplainsWhatBreaks() {
        let missing = Dependencies.missing(finder: without("ffmpeg", "gs"))
        XCTAssertEqual(Dependencies.summary(missing), "ffmpeg (videos and PNG files), ghostscript (PDFs)")
    }

    func testHomebrewDetection() {
        XCTAssertFalse(Dependencies.homebrewInstalled(finder: without("brew")))
    }

    // MARK: In the model

    private func makeModel(in directory: URL, finder: @escaping (String) -> String?) -> CompressorModel {
        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: directory,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        return CompressorModel(context: context, toolFinder: finder)
    }

    func testModelReportsMissingToolsAtLaunchAndRechecksOnDemand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("deps-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        nonisolated(unsafe) var installed = false
        let model = makeModel(in: directory) { name in
            (name == "gs" && !installed) ? nil : "/opt/homebrew/bin/\(name)"
        }
        XCTAssertEqual(model.missingRequired.map(\.formula), ["ghostscript"])

        installed = true // the user ran `brew install ghostscript` and pressed "Check again"
        model.refreshDependencies()
        XCTAssertTrue(model.missingRequired.isEmpty)
    }

    func testOptionalTipCanBeDismissedForGood() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let finder = without("oxipng")

        let model = makeModel(in: directory, finder: finder)
        XCTAssertEqual(model.missingOptional.map(\.formula), ["oxipng"])
        XCTAssertFalse(model.hideOptionalHint)

        model.dismissOptionalHint()
        XCTAssertTrue(makeModel(in: directory, finder: finder).hideOptionalHint, "dismissal should survive a relaunch")
    }

    func testCopyInstallCommandPutsItOnTheClipboard() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(in: directory, finder: without("ffmpeg", "gs"))
        let saved = NSPasteboard.general.string(forType: .string)
        defer { NSPasteboard.general.clearContents(); if let saved { NSPasteboard.general.setString(saved, forType: .string) } }

        model.copyInstallCommand(model.missingRequired)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "brew install ffmpeg ghostscript")
    }

    func testRealMachineStatusIsConsistent() {
        // On this Mac every required tool is installed (the app was built and tested with them).
        XCTAssertTrue(Dependencies.missing(optional: false).isEmpty, "install: \(Dependencies.installCommand(Dependencies.missing(optional: false)))")
    }
}
