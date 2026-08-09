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
        Task {
            await restoreSelection()
            applyLaunchRequest()
        }
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
        options = ToolOptionDefaults.options(for: tool, preserving: options)
    }

    private func restoreSelection() async {
        if let id = await preferences.loadSelectedToolID(), ToolCatalog.tool(id: id) != nil {
            select(toolID: id)
        } else {
            syncOptions(for: selectedTool)
        }
    }

    private func applyLaunchRequest() {
        let payload = context.launchRequest.payload
        if let actionID = payload["quickGlassActionID"],
           let action = QuickGlassActionCatalog.action(id: actionID) {
            select(toolID: action.toolID)
            options = ToolOptionDefaults.options(
                for: selectedTool,
                preserving: options,
                overrides: action.optionOverrides
            )
        } else if let toolID = payload["toolID"] {
            select(toolID: toolID)
        }
        let selectedText = payload["selectedText"]
            ?? context.launchRequest.query
        if !selectedText.isEmpty {
            primaryInput = selectedText
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
