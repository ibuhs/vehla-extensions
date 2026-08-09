import BSON
import XCTest
@testable import ToolboxWorkspace

final class ToolboxWorkspaceTests: XCTestCase {
    private var tempDir: URL!
    private var worker: ToolWorker!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        worker = ToolWorker(dataDirectory: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testJSONFormatAndMinify() async throws {
        let formatted = try await worker.execute(
            ToolRequest(
                toolID: "json.formatter",
                primary: #"{"b":1,"a":2}"#,
                secondary: "",
                options: [:]
            )
        )
        XCTAssertTrue(formatted.text.contains("\n"))
        let minified = try await worker.execute(
            ToolRequest(
                toolID: "json.minifier",
                primary: formatted.text,
                secondary: "",
                options: [:]
            )
        )
        XCTAssertFalse(minified.text.contains("\n"))
    }

    func testBase64RoundTrip() async throws {
        let encoded = try await worker.execute(
            ToolRequest(
                toolID: "enc.base64",
                primary: "hello toolbox",
                secondary: "",
                options: ["mode": "encode"]
            )
        )
        let decoded = try await worker.execute(
            ToolRequest(
                toolID: "enc.base64",
                primary: encoded.text,
                secondary: "",
                options: ["mode": "decode"]
            )
        )
        XCTAssertEqual(decoded.text, "hello toolbox")
    }

    func testSHA256() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "crypto.sha256",
                primary: "abc",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertEqual(
            output.text,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testBcryptRoundTrip() async throws {
        let hashed = try await worker.execute(
            ToolRequest(
                toolID: "crypto.bcrypt",
                primary: "secret",
                secondary: "",
                options: ["mode": "hash", "cost": "4"]
            )
        )
        XCTAssertTrue(hashed.text.hasPrefix("$2"))
        let verified = try await worker.execute(
            ToolRequest(
                toolID: "crypto.bcrypt",
                primary: "secret",
                secondary: hashed.text,
                options: ["mode": "verify"]
            )
        )
        XCTAssertTrue(verified.text.lowercased().contains("matches"))
    }

    func testArgon2idRoundTrip() async throws {
        let hashed = try await worker.execute(
            ToolRequest(
                toolID: "crypto.argon2",
                primary: "secret",
                secondary: "",
                options: [
                    "mode": "hash",
                    "memoryKiB": "16",
                    "iterations": "1",
                    "parallelism": "1",
                ]
            )
        )
        XCTAssertTrue(hashed.text.hasPrefix("$argon2id$"))
        let verified = try await worker.execute(
            ToolRequest(
                toolID: "crypto.argon2",
                primary: "secret",
                secondary: hashed.text,
                options: ["mode": "verify"]
            )
        )
        XCTAssertTrue(verified.text.lowercased().contains("matches"))
    }

    func testBSONDecodeToJSON() async throws {
        var document = Document()
        document["hello"] = "world"
        document["n"] = 42
        let hex = document.makeData().map { String(format: "%02x", $0) }.joined()
        let output = try await worker.execute(
            ToolRequest(toolID: "json.bson", primary: hex, secondary: "", options: [:])
        )
        XCTAssertTrue(output.text.contains("hello"))
        XCTAssertTrue(output.text.contains("world"))
        XCTAssertTrue(output.text.contains("42"))
    }

    func testHTMLPlaygroundPreview() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "web.htmlPlayground",
                primary: "<h1>Hi</h1>",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertNotNil(output.previewHTML)
        XCTAssertTrue(output.previewHTML?.contains("<h1>Hi</h1>") == true)
    }

    func testYAMLAndJSONPathAndEmoji() async throws {
        let yaml = try await worker.execute(
            ToolRequest(
                toolID: "json.yaml",
                primary: "name: Ada\nitems:\n  - 1\n  - 2\n",
                secondary: "",
                options: ["direction": "yaml-to-json"]
            )
        )
        XCTAssertTrue(yaml.text.contains("Ada"))
        let path = try await worker.execute(
            ToolRequest(
                toolID: "json.jsonpath",
                primary: #"{"users":[{"name":"Ada","age":36},{"name":"Grace","age":40}]}"#,
                secondary: "$.users[?(@.age>38)].name",
                options: [:]
            )
        )
        XCTAssertTrue(path.text.contains("Grace"))
        let emoji = try await worker.execute(
            ToolRequest(
                toolID: "enc.emoji",
                primary: "ship :rocket: :fire:",
                secondary: "",
                options: ["mode": "encode"]
            )
        )
        XCTAssertTrue(emoji.text.contains("🚀"))
        XCTAssertTrue(emoji.text.contains("🔥"))
    }

    func testHighlightAndMarkdownPreview() async throws {
        let highlight = try await worker.execute(
            ToolRequest(
                toolID: "code.highlight",
                primary: "let value = 42\n// comment",
                secondary: "",
                options: ["language": "swift"]
            )
        )
        XCTAssertNotNil(highlight.previewHTML)
        let md = try await worker.execute(
            ToolRequest(
                toolID: "text.mdEditor",
                primary: "# Title\n\nHello **world**",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertNotNil(md.previewHTML)
        XCTAssertTrue(md.previewHTML?.contains("<h1>") == true)
    }

    func testSQLFormatter() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "sql.formatter",
                primary: "select id,name from users where active=1;",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertTrue(output.text.uppercased().contains("SELECT"))
        XCTAssertTrue(output.text.contains("\n"))
    }

    func testSQLFilePathSupport() async throws {
        let sqlFile = tempDir.appendingPathComponent("schema.sql")
        try "create table users (id integer primary key, name text);".write(
            to: sqlFile,
            atomically: true,
            encoding: .utf8
        )
        let fromPathOption = try await worker.execute(
            ToolRequest(
                toolID: "sql.formatter",
                primary: "",
                secondary: "",
                options: ["sqlPath": sqlFile.path]
            )
        )
        XCTAssertTrue(fromPathOption.text.uppercased().contains("CREATE"))
        let fromPrimaryPath = try await worker.execute(
            ToolRequest(
                toolID: "sql.formatter",
                primary: sqlFile.path,
                secondary: "",
                options: [:]
            )
        )
        XCTAssertTrue(fromPrimaryPath.text.uppercased().contains("TABLE"))
        let browseDump = try await worker.execute(
            ToolRequest(
                toolID: "sql.sqliteBrowser",
                primary: "",
                secondary: "",
                options: ["dbPath": sqlFile.path]
            )
        )
        XCTAssertTrue(browseDump.text.contains("SQL file:"))
    }

    func testSQLDumpAsDbPathRunsQueryInMemory() async throws {
        let sqlFile = tempDir.appendingPathComponent("customers.sql")
        try """
        CREATE TABLE Customers (id INTEGER PRIMARY KEY, name TEXT);
        INSERT INTO Customers(name) VALUES ('Ada'), ('Grace');
        """.write(to: sqlFile, atomically: true, encoding: .utf8)

        let output = try await worker.execute(
            ToolRequest(
                toolID: "sql.runner",
                primary: "select * from Customers;",
                secondary: "",
                options: ["dbPath": sqlFile.path]
            )
        )
        XCTAssertTrue(output.text.contains("Ada"))
        XCTAssertTrue(output.text.contains("Grace"))
        XCTAssertTrue(output.meta?.contains("memory") == true)
    }

    func testSQLiteBrowserAndQuery() async throws {
        let db = tempDir.appendingPathComponent("sample.db").path
        _ = try await worker.execute(
            ToolRequest(
                toolID: "sql.sqliteEditor",
                primary: "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO items(name) VALUES ('a'), ('b');",
                secondary: "",
                options: ["dbPath": db]
            )
        )
        let browse = try await worker.execute(
            ToolRequest(
                toolID: "sql.sqliteBrowser",
                primary: "",
                secondary: "",
                options: ["dbPath": db]
            )
        )
        XCTAssertTrue(browse.text.contains("items"))
        let rows = try await worker.execute(
            ToolRequest(
                toolID: "sql.runner",
                primary: "SELECT name FROM items ORDER BY name",
                secondary: "",
                options: ["dbPath": db]
            )
        )
        XCTAssertTrue(rows.text.contains("a"))
        XCTAssertTrue(rows.text.contains("b"))
    }

    func testCodeDiffAndSnippets() async throws {
        let diff = try await worker.execute(
            ToolRequest(
                toolID: "code.diff",
                primary: "one\ntwo",
                secondary: "one\nthree",
                options: [:]
            )
        )
        XCTAssertTrue(diff.text.contains("+ three") || diff.text.contains("- two"))
        _ = try await worker.execute(
            ToolRequest(
                toolID: "code.snippets",
                primary: "print(1)",
                secondary: "",
                options: ["action": "save", "name": "demo", "language": "python"]
            )
        )
        let list = try await worker.execute(
            ToolRequest(
                toolID: "code.snippets",
                primary: "",
                secondary: "",
                options: ["action": "list"]
            )
        )
        XCTAssertTrue(list.text.contains("demo"))
    }

    func testCatalogAllReady() {
        XCTAssertEqual(ToolCatalog.all.count, 196)
        XCTAssertEqual(Set(ToolCatalog.all.map(\.id)).count, 196)
        XCTAssertFalse(ToolCatalog.all.contains { $0.status == .stub })
        XCTAssertNotNil(ToolCatalog.tool(id: "code.gist"))
        XCTAssertFalse(ToolCatalog.tools(in: .generators).isEmpty)
        XCTAssertFalse(ToolCatalog.tools(in: .web).isEmpty)
        XCTAssertFalse(ToolCatalog.tools(in: .networking).isEmpty)
    }

    func testGeneratorsAndContrast() async throws {
        let fake = try await worker.execute(
            ToolRequest(toolID: "gen.fake", primary: "", secondary: "", options: ["count": "2"])
        )
        XCTAssertTrue(fake.text.contains("email"))
        XCTAssertTrue(fake.text.contains("company"))
        XCTAssertTrue(fake.text.contains("address"))
        let contrast = try await worker.execute(
            ToolRequest(
                toolID: "web.contrast",
                primary: "#000000",
                secondary: "#FFFFFF",
                options: [:]
            )
        )
        XCTAssertTrue(contrast.text.contains("21"))
        let cidr = try await worker.execute(
            ToolRequest(toolID: "net.cidr", primary: "10.0.0.0/24", secondary: "", options: [:])
        )
        XCTAssertTrue(cidr.text.contains("broadcast: 10.0.0.255"))
    }

    func testJQAndJMESPathDeepQueries() async throws {
        let doc = #"{"users":[{"name":"Ada","age":36},{"name":"Grace","age":22}],"meta":{"ok":true}}"#
        let jq = try await worker.execute(
            ToolRequest(
                toolID: "json.jq",
                primary: doc,
                secondary: #".users | map(select(.age > 30)) | .[0].name"#,
                options: [:]
            )
        )
        XCTAssertTrue(jq.text.contains("Ada"))
        let jmes = try await worker.execute(
            ToolRequest(
                toolID: "json.jmespath",
                primary: doc,
                secondary: "users[?age > `30`].name",
                options: [:]
            )
        )
        XCTAssertTrue(jmes.text.contains("Ada"), jmes.text)
    }

    func testUserAgentAndLayoutPreviews() async throws {
        let ua = try await worker.execute(
            ToolRequest(
                toolID: "net.userAgent",
                primary: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertTrue(ua.text.contains("browser: Safari"))
        XCTAssertTrue(ua.text.contains("os: macOS"))
        XCTAssertTrue(ua.text.contains("device: desktop"))

        let flex = try await worker.execute(
            ToolRequest(
                toolID: "web.flexbox",
                primary: "",
                secondary: "",
                options: ["direction": "row", "items": "3"]
            )
        )
        XCTAssertNotNil(flex.previewHTML)
        XCTAssertTrue(flex.previewHTML?.contains("display: flex") == true)

        let grid = try await worker.execute(
            ToolRequest(
                toolID: "web.grid",
                primary: "",
                secondary: "",
                options: ["cols": "2", "rows": "2"]
            )
        )
        XCTAssertNotNil(grid.previewHTML)
        XCTAssertTrue(grid.previewHTML?.contains("display: grid") == true)
    }

    func testOptionsOnlyToolsHidePrimaryEditor() {
        let uuid = ToolCatalog.tool(id: "gen.uuid")
        XCTAssertEqual(uuid?.inputKind, ToolInputKind.none)
        XCTAssertFalse(uuid?.showsPrimaryEditor ?? true)
        let password = ToolCatalog.tool(id: "crypto.password")
        XCTAssertFalse(password?.showsPrimaryEditor ?? true)
        let flex = ToolCatalog.tool(id: "web.flexbox")
        XCTAssertFalse(flex?.showsPrimaryEditor ?? true)
    }

    func testPostgresHelperOfflineUX() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "sql.postgres",
                primary: "",
                secondary: "",
                options: [:]
            )
        )
        XCTAssertTrue(output.text.lowercased().contains("connection examples") || output.text.contains("psql") || output.text.contains("SELECT"))
        XCTAssertTrue(output.text.contains("postgres://") || output.text.contains("SELECT"))
    }

    func testFileHashFromEditorText() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "crypto.fileHash",
                primary: "abc",
                secondary: "",
                options: ["algorithm": "sha256"]
            )
        )
        XCTAssertTrue(output.text.contains("sha256:"))
        XCTAssertTrue(
            output.text.contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        )
    }

    func testGistRequiresSecret() async throws {
        do {
            _ = try await worker.execute(
                ToolRequest(
                    toolID: "code.gist",
                    primary: "hello",
                    secondary: "",
                    options: ["filename": "hi.txt"]
                )
            )
            XCTFail("Expected gist upload to fail without githubToken")
        } catch {
            let message = String(describing: error).lowercased()
            XCTAssertTrue(message.contains("githubtoken") || message.contains("secret"))
        }
    }

    func testCodeScreenshotPreview() async throws {
        let output = try await worker.execute(
            ToolRequest(
                toolID: "code.screenshot",
                primary: "print(\"hi\")",
                secondary: "",
                options: ["language": "python"]
            )
        )
        XCTAssertNotNil(output.previewHTML)
        XCTAssertTrue(output.previewHTML?.contains("data:image/png;base64,") == true)
    }

    func testQuickGlassCatalogIsCuratedAndRunnable() throws {
        let expectedIDs: Set<String> = [
            "json.format", "json.minify", "json.validate",
            "base64.encode", "base64.decode", "url.encode", "url.decode",
            "html.encode", "html.decode", "hex.encode", "hex.decode", "rot13",
            "hash.sha1", "hash.sha256", "hash.sha512", "hash.sha3-256", "hash.md5",
            "date.unix-to-iso", "date.iso-to-unix", "date.validate-iso",
            "text.count-characters", "text.count-words", "text.count-lines", "text.trim",
            "text.uppercase", "text.lowercase", "text.title-case", "text.camel-case",
            "text.snake-case", "text.slug", "text.dedupe-lines", "text.sort-lines",
            "text.sort-lines-descending", "text.reverse-lines",
            "code.format-sql", "code.format-html", "code.format-css", "code.format-yaml",
            "code.format-xml",
        ]
        XCTAssertEqual(Set(QuickGlassActionCatalog.all.map(\.id)), expectedIDs)
        XCTAssertEqual(QuickGlassActionCatalog.all.count, expectedIDs.count)

        for action in QuickGlassActionCatalog.all {
            let request = try action.request(selectedText: "sample")
            XCTAssertEqual(request.toolID, action.toolID)
            XCTAssertEqual(request.primary, "sample")
            XCTAssertEqual(
                Set(request.options.keys),
                Set(ToolCatalog.tool(id: action.toolID)?.optionKeys ?? [])
            )
        }
    }

    func testQuickGlassUsesSharedDefaultsAndOverrides() throws {
        let base64 = try XCTUnwrap(QuickGlassActionCatalog.action(id: "base64.decode"))
        XCTAssertEqual(
            try base64.request(selectedText: "aGVsbG8=").options["mode"],
            "decode"
        )

        let sort = try XCTUnwrap(
            QuickGlassActionCatalog.action(id: "text.sort-lines-descending")
        )
        XCTAssertEqual(
            try sort.request(selectedText: "a\nb").options["order"],
            "desc"
        )

        let unix = try XCTUnwrap(QuickGlassActionCatalog.action(id: "date.unix-to-iso"))
        let unixOptions = try unix.request(selectedText: "0").options
        XCTAssertEqual(unixOptions["mode"], "to-date")
        XCTAssertEqual(unixOptions["timezone"], TimeZone.current.identifier)
    }

    func testQuickGlassRepresentativeExecution() async throws {
        let encoded = try XCTUnwrap(QuickGlassActionCatalog.action(id: "base64.encode"))
        let encodedOutput = try await worker.execute(
            try encoded.request(selectedText: "hello")
        )
        XCTAssertEqual(encodedOutput.text, "aGVsbG8=")

        let uppercase = try XCTUnwrap(QuickGlassActionCatalog.action(id: "text.uppercase"))
        let uppercaseOutput = try await worker.execute(
            try uppercase.request(selectedText: "Hello world")
        )
        XCTAssertEqual(uppercaseOutput.text, "HELLO WORLD")

        let count = try XCTUnwrap(QuickGlassActionCatalog.action(id: "text.count-words"))
        let countOutput = try await worker.execute(
            try count.request(selectedText: "one two three")
        )
        XCTAssertTrue(countOutput.text.contains("3"))
    }

    func testQuickGlassManifestMatchesRuntimeCatalog() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("extension.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, QuickGlassActionCatalog.all.count)
        for (entry, action) in zip(entries, QuickGlassActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.id)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(
                entry["delivery"],
                action.delivery == .replaceSelection ? "replaceSelection" : "compactResult"
            )
        }
    }
}
