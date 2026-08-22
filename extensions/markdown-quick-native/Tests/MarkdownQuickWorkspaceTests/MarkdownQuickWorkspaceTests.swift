import XCTest
import VehlaNativeUISDK
@testable import MarkdownQuickWorkspace

final class MarkdownQuickWorkspaceTests: XCTestCase {
    func testNormalizesHeadingsAndBlankLines() throws {
        let input = "#Title\n\n\n\nParagraph  \n"
        XCTAssertEqual(
            try MarkdownEngine.normalize(input),
            "# Title\n\nParagraph"
        )
    }

    func testStripsMarkdownToPlainText() throws {
        let input = """
        # Hello
        A [link](https://example.com) and **bold**.
        ```
        code
        ```
        """
        let stripped = try MarkdownEngine.strip(input)
        XCTAssertTrue(stripped.contains("Hello"))
        XCTAssertTrue(stripped.contains("A link and bold."))
        XCTAssertTrue(stripped.contains("code"))
        XCTAssertFalse(stripped.contains("**"))
        XCTAssertFalse(stripped.contains("# Hello"))
    }

    func testFormatsPipeTables() throws {
        let input = """
        Before
        | Name | Qty |
        |---|---|
        | Tea | 2 |
        | Chocolate | 10 |
        After
        """
        let formatted = try MarkdownEngine.formatTables(input)
        XCTAssertTrue(formatted.contains("| Name      | Qty |"))
        XCTAssertTrue(formatted.contains("| --------- | --- |"))
        XCTAssertTrue(formatted.contains("| Chocolate | 10  |"))
        XCTAssertTrue(formatted.contains("Before"))
        XCTAssertTrue(formatted.contains("After"))
    }

    func testUnwrapsAndExtractsLinks() throws {
        let input = "See [Docs](https://example.com/docs) and <https://example.org>."
        XCTAssertEqual(
            try MarkdownEngine.unwrapLinks(input),
            "See https://example.com/docs and https://example.org."
        )
        XCTAssertEqual(
            try MarkdownEngine.renderLinks(input),
            "Docs — https://example.com/docs\nhttps://example.org"
        )
    }

    func testExtractsHeadingsAsOutline() throws {
        let input = "# Title\n## Section\n### Detail"
        XCTAssertEqual(
            try MarkdownEngine.renderHeadings(input),
            "Title\n  Section\n    Detail"
        )
    }

    func testWorkerRunsCatalogActions() async throws {
        let normalized = try await MarkdownWorker.shared.perform(
            .normalize,
            selectedText: "##Hello"
        )
        XCTAssertEqual(normalized, "## Hello")
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
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.markdown-quick")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertFalse(capabilities.contains("networkAccess"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, MarkdownQuickActionCatalog.all.count)
        for (entry, action) in zip(entries, MarkdownQuickActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(
                entry["delivery"],
                action.delivery == .replaceSelection ? "replaceSelection" : "compactResult"
            )
        }
    }
}
