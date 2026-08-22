import XCTest
import VehlaNativeUISDK
@testable import LinkLensWorkspace

final class LinkLensWorkspaceTests: XCTestCase {
    func testExtractsStandaloneAndEmbeddedURLs() {
        let text = """
        See https://example.com/a and [docs](https://example.com/b)
        also www.example.org/c
        """
        let urls = LinkEngine.extract(text).map(\.url.absoluteString)
        XCTAssertTrue(urls.contains("https://example.com/a"))
        XCTAssertTrue(urls.contains("https://example.com/b"))
        XCTAssertTrue(urls.contains("https://www.example.org/c"))
    }

    func testRemovesTrackingParameters() throws {
        let input = "https://example.com/path?id=1&utm_source=news&fbclid=abc&keep=yes#frag"
        let cleaned = try LinkEngine.replaceEachURL(in: input, transform: LinkEngine.clean)
        XCTAssertEqual(cleaned, "https://example.com/path?id=1&keep=yes")
    }

    func testUnwrapsGoogleAndOutlookWrappers() {
        let google = URL(string: "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fx%3Fid%3D1")!
        XCTAssertEqual(
            LinkEngine.unwrapLocally(google).absoluteString,
            "https://example.com/x?id=1"
        )

        let outlook = URL(string: "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.com%2Fmail")!
        XCTAssertEqual(
            LinkEngine.unwrapLocally(outlook).absoluteString,
            "https://example.com/mail"
        )
    }

    func testDecodesProofpointWrapper() {
        let encoded = "https-3A__example.com_path-3Fq-3D1"
        XCTAssertEqual(LinkEngine.decodeProofpoint(encoded), "https://example.com/path?q=1")
        let url = URL(string: "https://urldefense.proofpoint.com/v2/url?u=\(encoded)")!
        XCTAssertEqual(
            LinkEngine.unwrapLocally(url).absoluteString,
            "https://example.com/path?q=1"
        )
    }

    func testInspectShowsHostAndQuery() {
        let url = URL(string: "https://Example.com:8443/docs?q=1#top")!
        let report = LinkEngine.inspect([url])
        XCTAssertTrue(report.contains("Scheme: https"))
        XCTAssertTrue(report.contains("Host:"))
        XCTAssertTrue(report.contains("Path: /docs"))
        XCTAssertTrue(report.contains("Query: q=1"))
        XCTAssertTrue(report.contains("Fragment: top"))
    }

    func testSafetyFlagsCredentialsAndDangerousSchemes() {
        let credential = URL(string: "https://user:pass@example.com")!
        let script = URL(string: "javascript:alert(1)")!
        let report = LinkEngine.safetyReport(
            urls: [credential, script],
            redirectHops: [:]
        )
        XCTAssertTrue(report.contains("credentials"))
        XCTAssertTrue(report.contains("dangerous scheme"))
        XCTAssertTrue(report.contains("Risk: High"))
    }

    func testWorkerCleansAndExtractsOffCaller() async throws {
        let cleaned = try await LinkWorker.shared.perform(
            .clean,
            selectedText: "https://example.com/?utm_campaign=spring&ok=1"
        )
        XCTAssertEqual(cleaned, "https://example.com/?ok=1")

        let extracted = try await LinkWorker.shared.perform(
            .extract,
            selectedText: "a https://one.example/x b https://two.example/y"
        )
        XCTAssertEqual(extracted, "https://one.example/x\nhttps://two.example/y")
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
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.link-lens")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("networkAccess"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, LinkLensActionCatalog.all.count)
        for (entry, action) in zip(entries, LinkLensActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(
                entry["delivery"],
                action.delivery == .replaceSelection ? "replaceSelection" : "compactResult"
            )
        }
    }

    func testUnknownActionIsRejected() {
        XCTAssertNil(LinkLensActionCatalog.action(id: "url.encode"))
    }
}
