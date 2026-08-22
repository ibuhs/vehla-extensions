import XCTest
import VehlaNativeUISDK
@testable import DataExtractorWorkspace

final class DataExtractorWorkspaceTests: XCTestCase {
    private let sample = """
    Reach Ada at ada@example.com or +1 (555) 123-4567.
    Also ping @ada and #launch. Server is 10.0.0.8.
    Duplicate ada@example.com and 2001:db8::1.
    """

    func testExtractsEmailsPhonesAndIPs() throws {
        XCTAssertEqual(
            try DataExtractorEngine.emails(sample),
            "ada@example.com"
        )
        XCTAssertEqual(
            try DataExtractorEngine.phones(sample),
            "+1 (555) 123-4567"
        )
        XCTAssertEqual(
            try DataExtractorEngine.ips(sample),
            "10.0.0.8\n2001:db8::1"
        )
        XCTAssertEqual(try DataExtractorEngine.ips("loopback ::1 and fe80::1"), "::1\nfe80::1")
        XCTAssertThrowsError(try DataExtractorEngine.ips("Meet at 12:30 or 10:00:00."))
    }

    func testExtractsMentionsAndHashtags() throws {
        XCTAssertEqual(try DataExtractorEngine.mentions(sample), "@ada")
        XCTAssertEqual(try DataExtractorEngine.hashtags(sample), "#launch")
        XCTAssertEqual(DataExtractorEngine.extractMentions("ada@example.com"), [])
    }

    func testExtractAllAndCSV() throws {
        let all = try DataExtractorEngine.all(sample)
        XCTAssertTrue(all.contains("Emails\nada@example.com"))
        XCTAssertTrue(all.contains("Phones\n+1 (555) 123-4567"))
        XCTAssertTrue(all.contains("Mentions\n@ada"))
        XCTAssertEqual(
            try DataExtractorEngine.csv("ada@example.com and #launch"),
            "type,value\nemail,ada@example.com\nhashtag,#launch"
        )
    }

    func testWorkerRunsCatalogActions() async throws {
        let emails = try await DataExtractorWorker.shared.perform(
            .emails,
            selectedText: "Write to ada@example.com"
        )
        XCTAssertEqual(emails, "ada@example.com")
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
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.data-extractor")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertFalse(capabilities.contains("networkAccess"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, DataExtractorActionCatalog.all.count)
        for (entry, action) in zip(entries, DataExtractorActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(entry["delivery"], "compactResult")
        }
    }
}
