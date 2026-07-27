import Combine
import Foundation
import VehlaNativeUISDK

@MainActor
final class ThemeCoordinator: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme

    init(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }

    func update(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var selectedCategory: ToolCategory = .json
    @Published var selectedToolID: String = ToolCatalog.jsonFirstID
    @Published var searchText = ""
    @Published var primaryInput = ""
    @Published var secondaryInput = ""
    @Published var options: [String: String] = [:]
    @Published var output = ""
    @Published var previewHTML: String?
    @Published var meta: String?
    @Published var errorMessage: String?
    @Published var isRunning = false

    let context: VehlaWorkspaceContext
    let theme: ThemeCoordinator

    private let worker: ToolWorker
    private let preferences: PreferencesStore
    private var runTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var generation = UUID()

    init(context: VehlaWorkspaceContext, theme: ThemeCoordinator) {
        self.context = context
        self.theme = theme
        worker = ToolWorker(dataDirectory: context.dataDirectory)
        preferences = PreferencesStore(directory: context.dataDirectory)
        Task { await restoreSelection() }
    }

    deinit {
        runTask?.cancel()
        persistTask?.cancel()
    }

    var selectedTool: ToolDefinition {
        ToolCatalog.tool(id: selectedToolID) ?? ToolCatalog.all[0]
    }

    var filteredTools: [ToolDefinition] {
        let base = ToolCatalog.tools(in: selectedCategory)
        guard !searchText.isEmpty else { return base }
        return ToolCatalog.all.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.subtitle.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    func select(category: ToolCategory) {
        selectedCategory = category
        if let first = ToolCatalog.tools(in: category).first {
            select(toolID: first.id)
        }
    }

    func select(toolID: String) {
        guard let tool = ToolCatalog.tool(id: toolID) else { return }
        selectedToolID = tool.id
        selectedCategory = tool.category
        errorMessage = nil
        output = ""
        previewHTML = nil
        meta = nil
        syncOptions(for: tool)
        persistSelection()
    }

    func run() {
        let tool = selectedTool
        if tool.status == .stub {
            errorMessage = nil
            output = ""
            previewHTML = nil
            meta = nil
            errorMessage = tool.stubReason ?? "Coming soon."
            return
        }
        runTask?.cancel()
        let token = UUID()
        generation = token
        isRunning = true
        errorMessage = nil
        var runOptions = options
        if tool.id == "code.gist", runOptions["githubToken"] == nil || runOptions["githubToken"]?.isEmpty == true {
            runOptions["githubToken"] = context.secret(named: "githubToken") ?? ""
        }
        if tool.id.hasPrefix("sql."),
           (runOptions["dbPath"] == nil || runOptions["dbPath"]?.isEmpty == true),
           !secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            runOptions["dbPath"] = secondaryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let request = ToolRequest(
            toolID: tool.id,
            primary: primaryInput,
            secondary: secondaryInput,
            options: runOptions
        )
        runTask = Task { [worker] in
            let result: Result<ToolOutput, Error>
            do {
                // Hop off MainActor: worker is an actor.
                let output = try await worker.execute(request)
                result = .success(output)
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                guard self.generation == token else { return }
                self.isRunning = false
                switch result {
                case .success(let value):
                    self.output = value.text
                    self.previewHTML = value.previewHTML
                    self.meta = value.meta
                    self.errorMessage = nil
                case .failure(let error):
                    self.output = ""
                    self.previewHTML = nil
                    self.meta = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
        generation = UUID()
        isRunning = false
    }

    func clear() {
        primaryInput = ""
        secondaryInput = ""
        output = ""
        previewHTML = nil
        meta = nil
        errorMessage = nil
    }

    func copyOutput() {
        guard !output.isEmpty else { return }
        context.copyText(output)
    }

    private func syncOptions(for tool: ToolDefinition) {
        var next: [String: String] = [:]
        for key in tool.optionKeys {
            next[key] = options[key] ?? defaultOption(for: key, tool: tool)
        }
        options = next
    }

    private func defaultOption(for key: String, tool: ToolDefinition) -> String {
        switch key {
        case "mode":
            if tool.id == "crypto.bcrypt" || tool.id == "crypto.argon2" { return "hash" }
            if tool.id.hasPrefix("enc.") || tool.id.hasPrefix("crypto.aes") { return "encode" }
            if tool.id == "date.unix" { return "to-date" }
            if tool.id == "text.case" { return "upper" }
            return "encrypt"
        case "direction":
            if tool.id == "json.xml" { return "xml-to-json" }
            if tool.id == "json.yaml" { return "yaml-to-json" }
            if tool.id == "web.flexbox" { return "row" }
            return "toml-to-json"
        case "count", "paragraphs", "words": return "3"
        case "length": return "20"
        case "bytes", "size": return "21"
        case "iterations":
            return tool.id == "crypto.argon2" ? "2" : "100000"
        case "keyLength": return "32"
        case "salt": return "toolbox"
        case "algorithm": return "all"
        case "unit": return tool.id == "date.epoch" ? "ms" : "day"
        case "amount", "days", "interval": return "1"
        case "timezone": return TimeZone.current.identifier
        case "from":
            return tool.id == "gen.cssGradient" ? "#0ea5e9" : TimeZone.current.identifier
        case "to":
            return tool.id == "gen.cssGradient" ? "#a855f7" : "UTC"
        case "format": return "yyyy-MM-dd HH:mm:ss"
        case "freq": return "WEEKLY"
        case "minute": return "*/5"
        case "hour", "dom", "month", "dow": return "*"
        case "action":
            if tool.id == "code.snippets" { return "list" }
            if tool.id == "web.liveServer" || tool.id == "web.httpsServer" { return "start" }
            return "lap"
        case "charset": return "all"
        case "version": return "4"
        case "workerId": return "1"
        case "width": return "80"
        case "order": return "asc"
        case "find", "replace", "passphrase", "key", "signature", "target",
             "dbPath", "otherDbPath", "sqlPath", "filePath", "url", "password", "table",
             "hash", "description":
            return ""
        case "name":
            return tool.id == "gen.tailwindColor" ? "brand" : ""
        case "language": return "swift"
        case "filename":
            return tool.id == "code.gist" ? "snippet.txt" : "input.js"
        case "public": return "false"
        case "collection": return "items"
        case "host": return tool.id.hasPrefix("net.") ? "127.0.0.1" : "127.0.0.1"
        case "port":
            if tool.id == "web.httpsServer" { return "8443" }
            if tool.id == "web.liveServer" { return "8787" }
            if tool.id.hasPrefix("net.ssl") || tool.id == "net.tlsHandshake" || tool.id == "net.httpHeaders" {
                return "443"
            }
            if tool.id.hasPrefix("sql.redis") { return "6379" }
            if tool.id.hasPrefix("net.") { return "80" }
            return "8080"
        case "pattern": return "*"
        case "cost": return "10"
        case "memoryKiB": return "16384"
        case "parallelism": return "1"
        case "ports": return "22,80,443,8080"
        case "timeoutMs": return "400"
        case "prefix": return "24"
        case "type":
            if tool.id == "net.dns" { return "A" }
            if tool.id == "gen.cssGradient" { return "linear" }
            return "A"
        case "origin": return "https://example.com"
        case "method": return "GET"
        case "preset": return "desktop"
        case "justify": return "space-between"
        case "align": return "center"
        case "items": return "3"
        case "cols": return "3"
        case "rows": return "2"
        case "gap": return "12px"
        case "x": return "0"
        case "y": return "8"
        case "blur": return "24"
        case "spread": return "-4"
        case "color":
            if tool.id == "gen.cssShadow" { return "rgba(0,0,0,0.18)" }
            if tool.id == "gen.tailwindClass" { return "bg-slate-900 text-white" }
            return ""
        case "angle": return "135"
        case "duration": return "0.45s"
        case "easing": return "ease-out"
        case "layout": return "flex items-center"
        case "spacing": return "gap-3 px-4 py-2"
        case "text": return "text-sm font-medium"
        case "preheader": return "A simple transactional email"
        case "userAgent": return "*"
        case "disallow": return "/"
        case "columns": return "name,email"
        default: return ""
        }
    }

    private func restoreSelection() async {
        if let id = await preferences.loadSelectedToolID(), ToolCatalog.tool(id: id) != nil {
            select(toolID: id)
        } else {
            syncOptions(for: selectedTool)
        }
    }

    private func persistSelection() {
        let id = selectedToolID
        persistTask?.cancel()
        persistTask = Task { [preferences] in
            try? await Task.sleep(for: .milliseconds(200))
            await preferences.saveSelectedToolID(id)
        }
    }
}

extension ToolCatalog {
    static var jsonFirstID: String {
        tools(in: .json).first?.id ?? all[0].id
    }
}
