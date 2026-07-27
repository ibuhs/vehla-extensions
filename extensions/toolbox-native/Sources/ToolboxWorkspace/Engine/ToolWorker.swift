import Foundation

/// All tool computation runs in this actor (or nested actors). Never call from MainActor
/// with synchronous waiting — only `await`.
actor ToolWorker {
    private let json = JSONTools()
    private let encoding = EncodingTools()
    private let crypto = CryptoTools()
    private let date = DateTools()
    private let text = TextTools()
    private let code: CodeTools
    private let sql = SQLTools()
    private let generators = GeneratorTools()
    private let web = WebTools()
    private let networking = NetworkTools()

    init(dataDirectory: URL) {
        code = CodeTools(dataDirectory: dataDirectory)
    }

    func execute(_ request: ToolRequest) async throws -> ToolOutput {
        guard let tool = ToolCatalog.tool(id: request.toolID) else {
            throw ToolError.unknownTool(request.toolID)
        }
        if tool.status == .stub {
            throw ToolError.stub(tool.stubReason ?? "This tool is not available yet.")
        }
        try ToolLimits.guardSize(request.primary)
        if !request.secondary.isEmpty {
            try ToolLimits.guardSize(request.secondary, label: "Secondary input")
        }

        let started = ContinuousClock.now
        let output: ToolOutput
        switch tool.category {
        case .json:
            output = try await json.run(request)
        case .encoding:
            output = try await encoding.run(request)
        case .crypto:
            output = try await crypto.run(request)
        case .date:
            output = try await date.run(request)
        case .text:
            output = try await text.run(request)
        case .code:
            output = try await code.run(request)
        case .sql:
            output = try await sql.run(request)
        case .generators:
            output = try await generators.run(request)
        case .web:
            output = try await web.run(request)
        case .networking:
            output = try await networking.run(request)
        }
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1_000
            + Double(elapsed.components.attoseconds) / 1e15
        let metaBits = [output.meta, String(format: "%.1f ms", ms)].compactMap { $0 }
        return ToolOutput(
            ToolLimits.truncate(output.text),
            meta: metaBits.joined(separator: " · "),
            previewHTML: output.previewHTML.map(ToolLimits.truncate)
        )
    }
}
