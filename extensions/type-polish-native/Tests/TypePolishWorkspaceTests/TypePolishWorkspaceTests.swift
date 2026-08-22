import XCTest
import VehlaNativeUISDK
@testable import TypePolishWorkspace

final class TypePolishWorkspaceTests: XCTestCase {
    func testStraightensQuotes() throws {
        XCTAssertEqual(
            try TypePolishEngine.straightenQuotes("“Hello,” she said. ‘Yes.’"),
            "\"Hello,\" she said. 'Yes.'"
        )
    }

    func testCleansDashesAndEllipses() throws {
        XCTAssertEqual(
            try TypePolishEngine.cleanDashes("Wait—really… yes–no"),
            "Wait--really... yes-no"
        )
    }

    func testUnwrapsHardWrappedParagraphs() throws {
        let input = "This line is wrapped\nacross two rows.\n\nNext paragraph\nstays separate."
        XCTAssertEqual(
            try TypePolishEngine.unwrap(input),
            "This line is wrapped across two rows.\n\nNext paragraph stays separate."
        )
    }

    func testCollapsesSpacesAndNBSP() throws {
        XCTAssertEqual(
            try TypePolishEngine.collapseSpaces("Hello\u{00A0}\u{00A0}world   there\tnow"),
            "Hello world there now"
        )
    }

    func testStripsInvisibleMarks() throws {
        XCTAssertEqual(
            try TypePolishEngine.stripJunk("Hello\u{200B} world\u{00AD}"),
            "Hello world"
        )
    }

    func testPolishRunsEveryCleanup() throws {
        let input = "“Hello,”\nshe said—yes…  really\u{200B}."
        XCTAssertEqual(
            try TypePolishEngine.polish(input),
            "\"Hello,\" she said--yes... really."
        )
    }

    func testWorkerRunsCatalogActions() async throws {
        let output = try await TypePolishWorker.shared.perform(
            .straightenQuotes,
            selectedText: "“Hi”"
        )
        XCTAssertEqual(output, "\"Hi\"")
    }

    func testCatalogMatchesManifest() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("extension.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.type-polish")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertFalse(capabilities.contains("networkAccess"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, TypePolishActionCatalog.all.count)
        for (entry, action) in zip(entries, TypePolishActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(entry["delivery"], "replaceSelection")
        }
    }
}
