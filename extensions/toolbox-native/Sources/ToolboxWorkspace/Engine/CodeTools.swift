import Foundation

actor CodeTools {
    private let cli = CLIProcessRunner()
    private let snippets: SnippetStore

    init(dataDirectory: URL) {
        snippets = SnippetStore(directory: dataDirectory)
    }

    func run(_ request: ToolRequest) async throws -> ToolOutput {
        switch request.toolID {
        case "code.highlight":
            let language = request.options["language"] ?? "swift"
            let highlighted = CodeSyntax.highlight(request.primary, language: language)
            return ToolOutput(highlighted.text, meta: "syntax highlight", previewHTML: highlighted.html)
        case "code.formatter":
            let language = request.options["language"] ?? "auto"
            return try await format(request.primary, language: language)
        case "code.prettier":
            return try await runFormatterCLI(
                names: ["prettier"],
                args: ["--stdin-filepath", request.options["filename"] ?? "input.js"],
                stdin: request.primary
            )
        case "code.eslint":
            return try await runESLint(request.primary)
        case "code.swift":
            return try await runFormatterCLI(
                names: ["swift-format", "swiftformat"],
                argsFor: { name in name.hasSuffix("swiftformat") ? ["--stdin", "--stdout"] : [] },
                stdin: request.primary,
                fallbackLanguage: "swift"
            )
        case "code.python":
            return try await runFormatterCLI(
                names: ["ruff", "black"],
                argsFor: { name in
                    if name.hasSuffix("ruff") { return ["format", "-", "--quiet"] }
                    return ["-", "--quiet"]
                },
                stdin: request.primary,
                fallbackLanguage: "python"
            )
        case "code.sqlFormat", "code.html", "code.css", "code.yaml", "code.xml":
            let language: String = {
                switch request.toolID {
                case "code.sqlFormat": return "sql"
                case "code.html": return "html"
                case "code.css": return "css"
                case "code.yaml": return "yaml"
                default: return "xml"
                }
            }()
            return ToolOutput(CodeFormatters.generic(request.primary, language: language))
        case "code.java", "code.kotlin", "code.go", "code.rust", "code.csharp":
            return try await languageCLIFormat(request)
        case "code.diff":
            return ToolOutput(TextDiff.lineDiff(request.primary, request.secondary))
        case "code.ast":
            let language = request.options["language"] ?? "auto"
            return ToolOutput(CodeSyntax.astOutline(request.primary, language: language), meta: "ast")
        case "code.snippets":
            return try await snippetsHandle(request)
        case "code.screenshot":
            let rendered = try CodeScreenshot.renderPNG(
                text: request.primary,
                language: request.options["language"] ?? "swift"
            )
            let preview = """
            <!doctype html><html><head><meta charset="utf-8">
            <style>body{margin:0;background:#111;display:grid;place-items:center;min-height:100vh}
            img{max-width:100%;height:auto;box-shadow:0 12px 40px rgba(0,0,0,.45)}</style></head>
            <body><img alt="Code screenshot" src="data:image/png;base64,\(rendered.base64)"></body></html>
            """
            return ToolOutput(
                [
                    "Wrote PNG: \(rendered.path)",
                    "bytes: \(rendered.bytes)",
                    "base64:",
                    rendered.base64,
                ].joined(separator: "\n"),
                meta: "png preview",
                previewHTML: preview
            )
        case "code.gist":
            return try await uploadGist(request)
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func format(_ text: String, language: String) async throws -> ToolOutput {
        let detected = language == "auto" ? detectLanguage(text) : language
        if ["js", "javascript", "ts", "typescript", "json", "css", "html", "md", "markdown"].contains(detected) {
            if let path = await cli.which("prettier") {
                let result = try await cli.run(
                    executable: path,
                    arguments: ["--stdin-filepath", "input.\(detected == "typescript" ? "ts" : detected)"],
                    stdin: text
                )
                if result.exitCode == 0 { return ToolOutput(result.stdout, meta: "prettier · \(detected)") }
            }
        }
        return ToolOutput(CodeFormatters.generic(text, language: detected), meta: "builtin · \(detected)")
    }

    private func languageCLIFormat(_ request: ToolRequest) async throws -> ToolOutput {
        switch request.toolID {
        case "code.go":
            return try await runFormatterCLI(names: ["gofmt"], args: [], stdin: request.primary, fallbackLanguage: "go")
        case "code.rust":
            return try await runFormatterCLI(names: ["rustfmt"], args: [], stdin: request.primary, fallbackLanguage: "rust")
        case "code.java":
            return try await runFormatterCLI(
                names: ["google-java-format"],
                args: ["-"],
                stdin: request.primary,
                fallbackLanguage: "java"
            )
        case "code.kotlin":
            return try await runFormatterCLI(
                names: ["ktlint"],
                args: ["--format", "--stdin"],
                stdin: request.primary,
                fallbackLanguage: "kotlin"
            )
        case "code.csharp":
            return try await runFormatterCLI(
                names: ["dotnet"],
                args: ["format", "--help"],
                stdin: nil,
                fallbackLanguage: "csharp",
                allowFallbackAlways: true
            )
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func runESLint(_ source: String) async throws -> ToolOutput {
        guard let eslint = await cli.which("eslint") else {
            throw ToolError.failed("eslint not found on PATH. Install Node eslint to enable this tool.")
        }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbox-eslint-\(UUID().uuidString).js")
        try source.write(to: temp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: temp) }
        let result = try await cli.run(
            executable: eslint,
            arguments: [temp.path, "--format", "stylish"]
        )
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ToolOutput("No ESLint issues found.", meta: "exit \(result.exitCode)")
        }
        return ToolOutput(body, meta: "exit \(result.exitCode)")
    }

    private func runFormatterCLI(
        names: [String],
        args: [String] = [],
        argsFor: ((String) -> [String])? = nil,
        stdin: String?,
        fallbackLanguage: String? = nil,
        allowFallbackAlways: Bool = false
    ) async throws -> ToolOutput {
        for name in names {
            guard let path = await cli.which(name) else { continue }
            if allowFallbackAlways, fallbackLanguage != nil {
                // dotnet format isn't stdin-friendly; fall through to builtin.
                break
            }
            let arguments = argsFor?(name) ?? args
            let result = try await cli.run(executable: path, arguments: arguments, stdin: stdin)
            if result.exitCode == 0, !result.stdout.isEmpty {
                return ToolOutput(result.stdout, meta: name)
            }
            if result.exitCode != 0 {
                let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !err.isEmpty { throw ToolError.failed("\(name): \(err)") }
            }
        }
        if let fallbackLanguage, let stdin {
            return ToolOutput(
                CodeFormatters.generic(stdin, language: fallbackLanguage),
                meta: "builtin fallback · \(fallbackLanguage)"
            )
        }
        throw ToolError.failed("No formatter found on PATH for: \(names.joined(separator: ", "))")
    }

    private func snippetsHandle(_ request: ToolRequest) async throws -> ToolOutput {
        let action = (request.options["action"] ?? "list").lowercased()
        switch action {
        case "save", "add":
            let name = request.options["name"] ?? "snippet"
            try await snippets.save(name: name, body: request.primary, language: request.options["language"] ?? "")
            return ToolOutput("Saved snippet “\(name)”.", meta: "snippets")
        case "get", "load":
            let name = request.options["name"] ?? ""
            guard let body = try await snippets.get(name: name) else {
                throw ToolError.invalidInput("Snippet not found: \(name)")
            }
            return ToolOutput(body)
        case "delete", "remove":
            let name = request.options["name"] ?? ""
            try await snippets.delete(name: name)
            return ToolOutput("Deleted snippet “\(name)”.")
        default:
            let list = try await snippets.list()
            if list.isEmpty { return ToolOutput("No snippets saved yet. Set action=save and name=…") }
            return ToolOutput(list.map { "• \($0.name)  [\($0.language)]  \($0.updated)" }.joined(separator: "\n"))
        }
    }

    private func uploadGist(_ request: ToolRequest) async throws -> ToolOutput {
        let token = request.options["githubToken"] ?? ""
        guard !token.isEmpty else {
            throw ToolError.invalidInput("Set the githubToken secret in Vehla Store settings for Toolbox.")
        }
        let filename = request.options["filename"] ?? "snippet.txt"
        let description = request.options["description"] ?? "Uploaded from Vehla Toolbox"
        let isPublic = (request.options["public"] ?? "false").lowercased() == "true"
        let payload: [String: Any] = [
            "description": description,
            "public": isPublic,
            "files": [filename: ["content": request.primary]],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var req = URLRequest(url: URL(string: "https://api.github.com/gists")!)
        req.httpMethod = "POST"
        req.httpBody = data
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("Vehla-Toolbox", forHTTPHeaderField: "User-Agent")
        let (responseData, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw ToolError.failed("Unexpected Gist response (\(code)).")
        }
        if let html = object["html_url"] as? String {
            return ToolOutput(html, meta: "HTTP \(code)")
        }
        let message = object["message"] as? String ?? String(data: responseData, encoding: .utf8) ?? "Gist upload failed"
        throw ToolError.failed("HTTP \(code): \(message)")
    }

    private func detectLanguage(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return "json" }
        if trimmed.hasPrefix("SELECT") || trimmed.lowercased().hasPrefix("select") { return "sql" }
        if trimmed.contains("func ") || trimmed.contains("let ") { return "swift" }
        if trimmed.contains("def ") || trimmed.contains("import ") { return "python" }
        if trimmed.contains("{") && trimmed.contains(":") && trimmed.contains(";") { return "css" }
        if trimmed.contains("<") && trimmed.contains(">") { return "html" }
        return "text"
    }
}

actor SnippetStore {
    struct Item: Codable, Sendable {
        var name: String
        var body: String
        var language: String
        var updated: String
    }

    private let url: URL

    init(directory: URL) {
        url = directory.appendingPathComponent("snippets.json")
    }

    func list() throws -> [(name: String, language: String, updated: String)] {
        try load().map { ($0.name, $0.language, $0.updated) }.sorted { $0.name < $1.name }
    }

    func get(name: String) throws -> String? {
        try load().first { $0.name == name }?.body
    }

    func save(name: String, body: String, language: String) throws {
        var items = try load()
        let stamp = ISO8601DateFormatter().string(from: Date())
        if let index = items.firstIndex(where: { $0.name == name }) {
            items[index] = Item(name: name, body: body, language: language, updated: stamp)
        } else {
            items.append(Item(name: name, body: body, language: language, updated: stamp))
        }
        try save(items)
    }

    func delete(name: String) throws {
        var items = try load()
        items.removeAll { $0.name == name }
        try save(items)
    }

    private func load() throws -> [Item] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Item].self, from: data)
    }

    private func save(_ items: [Item]) throws {
        let data = try JSONEncoder().encode(items)
        try data.write(to: url, options: .atomic)
    }
}
