import XCTest
@testable import CoverArtSearchWorkspace

final class CoverArtSearchWorkspaceTests: XCTestCase {
    func testManifestVersionAndCapabilities() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("extension.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(manifest["version"] as? String, "1.0.1")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertTrue(capabilities.contains("networkAccess"))
        XCTAssertTrue(capabilities.contains("clipboardWrite"))
    }

    func testResultBuildsIMDbURL() {
        let result = CoverArtResult(
            id: "tt0012345",
            title: "A Film",
            subtitle: "Movie",
            kind: "movie",
            year: 2026,
            imageURL: URL(string: "https://example.com/poster.jpg")!,
            width: 960,
            height: 1422
        )

        XCTAssertEqual(result.imdbURL.absoluteString, "https://www.imdb.com/title/tt0012345/")
        XCTAssertEqual(result.dimensions, "960×1422")
        XCTAssertEqual(result.imageFileName, "A Film.jpg")
    }

    func testImageFileNameRemovesPathCharacters() {
        let result = CoverArtResult(
            id: "tt0012345",
            title: "Movie / Part: One",
            subtitle: "Movie",
            kind: "movie",
            year: nil,
            imageURL: URL(string: "https://example.com/poster.jpg")!,
            width: nil,
            height: nil
        )

        XCTAssertEqual(result.imageFileName, "Movie - Part- One.jpg")
    }

    func testEmptyQueryDoesNotNeedNetwork() async throws {
        let results = try await CoverArtSearchService.shared.search("   ")
        XCTAssertTrue(results.isEmpty)
    }
}
