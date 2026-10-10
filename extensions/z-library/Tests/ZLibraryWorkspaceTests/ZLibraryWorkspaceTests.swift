import XCTest
@testable import ZLibraryWorkspace

final class ZLibraryWorkspaceTests: XCTestCase {
    func testDecodesSearchResponse() throws {
        let data = Data(
            """
            {
              "books": [{
                "id": "123",
                "hash": "abc",
                "url": "https://example.com/book/123",
                "name": "A Useful Book",
                "authors": ["Ada Author"],
                "year": "2025",
                "extension": "epub",
                "size": "2 MB",
                "rating": "4.8"
              }],
              "page": 1,
              "total_pages": 3
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(ZLibrarySearchResponse.self, from: data)
        XCTAssertEqual(response.books.count, 1)
        XCTAssertEqual(response.books[0].name, "A Useful Book")
        XCTAssertEqual(response.books[0].extensionName, "epub")
        XCTAssertEqual(response.books[0].authorLine, "Ada Author")
        XCTAssertEqual(response.totalPages, 3)
    }

    func testConfiguredAndAutomaticCLICandidates() {
        let environment = ["PATH": "/custom/bin:/usr/bin"]
        XCTAssertEqual(
            ZLibraryCLI.candidatePaths(
                configuredPath: "/Applications/zlib",
                environment: environment,
                homeDirectory: "/Users/test"
            ),
            ["/Applications/zlib"]
        )
        XCTAssertEqual(
            ZLibraryCLI.candidatePaths(
                configuredPath: "custom-zlib",
                environment: environment,
                homeDirectory: "/Users/test"
            ),
            ["/custom/bin/custom-zlib", "/usr/bin/custom-zlib"]
        )
        XCTAssertTrue(
            ZLibraryCLI.candidatePaths(
                configuredPath: "",
                environment: environment,
                homeDirectory: "/Users/test"
            ).contains("/opt/homebrew/bin/zlib")
        )
    }

    func testManifestDeclaresNativeWorkspaceRequirements() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("extension.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(manifest["apiVersion"] as? Int, 2)
        XCTAssertEqual(manifest["version"] as? String, "1.0.3")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        XCTAssertEqual((manifest["workspaces"] as? [[String: Any]])?.count, 1)
        XCTAssertTrue(
            try XCTUnwrap(manifest["capabilities"] as? [String])
                .contains("persistentStorage")
        )
        XCTAssertEqual((manifest["commands"] as? [[String: Any]])?.count, 2)
    }
}
