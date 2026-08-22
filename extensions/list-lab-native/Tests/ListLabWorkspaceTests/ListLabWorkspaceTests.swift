import XCTest
import VehlaNativeUISDK
@testable import ListLabWorkspace

final class ListLabWorkspaceTests: XCTestCase {
    func testSplitsAndJoinsCommaLists() throws {
        XCTAssertEqual(
            try ListEngine.split("tea, milk, chocolate", separator: ","),
            "tea\nmilk\nchocolate"
        )
        XCTAssertEqual(
            try ListEngine.join("tea\n\nmilk\nchocolate\n", separator: ", "),
            "tea, milk, chocolate"
        )
    }

    func testSplitsAndJoinsPipeLists() throws {
        XCTAssertEqual(
            try ListEngine.split("tea | milk | chocolate", separator: "|"),
            "tea\nmilk\nchocolate"
        )
        XCTAssertEqual(
            try ListEngine.join("tea\nmilk\nchocolate", separator: " | "),
            "tea | milk | chocolate"
        )
    }

    func testShuffleIsAPermutation() throws {
        var generator = SeededGenerator(state: 42)
        let shuffled = try ListEngine.shuffle("a\nb\nc\nd", using: &generator)
        XCTAssertEqual(Set(shuffled.split(separator: "\n").map(String.init)), ["a", "b", "c", "d"])
        XCTAssertNotEqual(shuffled, "a\nb\nc\nd")
    }

    func testNumbersAndRenumbersLines() throws {
        XCTAssertEqual(
            try ListEngine.number("tea\nmilk"),
            "1. tea\n2. milk"
        )
        XCTAssertEqual(
            try ListEngine.number("3. tea\n1. milk"),
            "1. tea\n2. milk"
        )
    }

    func testQuotesWrapsAndUnwraps() throws {
        XCTAssertEqual(
            try ListEngine.quote("tea\nmilk"),
            "\"tea\"\n\"milk\""
        )
        XCTAssertEqual(
            try ListEngine.wrapParens("tea\nmilk"),
            "(tea)\n(milk)"
        )
        XCTAssertEqual(
            try ListEngine.unwrap("\"tea\"\n(milk)\n[chocolate]"),
            "tea\nmilk\nchocolate"
        )
        XCTAssertEqual(
            try ListEngine.unwrap("(tea\nand milk)"),
            "tea\nand milk"
        )
    }

    func testPrefixesEachItem() throws {
        XCTAssertEqual(
            try ListEngine.prefix("tea\nmilk", with: "- "),
            "- tea\n- milk"
        )
        XCTAssertThrowsError(try ListEngine.prefix("tea", with: "")) { error in
            XCTAssertEqual(error as? ListLabError, .emptyClipboard)
        }
    }

    func testWorkerRunsCatalogActions() async throws {
        let numbered = try await ListWorker.shared.perform(
            .number,
            selectedText: "tea\nmilk"
        )
        XCTAssertEqual(numbered, "1. tea\n2. milk")
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
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.list-lab")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertTrue(capabilities.contains("clipboardRead"))
        XCTAssertFalse(capabilities.contains("networkAccess"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, ListLabActionCatalog.all.count)
        for (entry, action) in zip(entries, ListLabActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(entry["delivery"], "replaceSelection")
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
