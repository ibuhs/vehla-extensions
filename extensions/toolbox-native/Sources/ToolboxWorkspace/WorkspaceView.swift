import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VehlaNativeUISDK
import WebKit

struct ToolboxWorkspaceView: View {
    @StateObject private var store: WorkspaceStore
    @ObservedObject private var theme: ThemeCoordinator

    init(context: VehlaWorkspaceContext, theme: ThemeCoordinator) {
        _store = StateObject(wrappedValue: WorkspaceStore(context: context, theme: theme))
        self.theme = theme
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
                .frame(width: 280)
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            ToolWorkbenchView(store: store)
                .frame(minWidth: 640)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 920, minHeight: 620)
        .background {
            ZStack {
                Color(nsColor: theme.theme.backgroundColor)
                Color(nsColor: theme.theme.surfaceColor)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(Color(nsColor: theme.theme.primaryTextColor))
        .tint(Color(nsColor: theme.theme.primaryTextColor))
        .preferredColorScheme(theme.theme.isDark ? .dark : .light)
    }
}

private struct SidebarView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                Text("Toolbox")
                    .font(.headline)
                Spacer()
                Text("\(ToolCatalog.tools(in: store.selectedCategory).count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ToolCategory.allCases) { category in
                        Button {
                            store.select(category: category)
                        } label: {
                            Label(category.rawValue.components(separatedBy: " ").first ?? category.rawValue,
                                  systemImage: category.systemImage)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    store.selectedCategory == category && store.searchText.isEmpty
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.primary.opacity(0.06)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search tools", text: $store.searchText)
                    .textFieldStyle(.plain)
                if !store.searchText.isEmpty {
                    Button {
                        store.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(10)

            if store.filteredTools.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No tools match")
                        .font(.callout.weight(.medium))
                    Text(
                        store.searchText.isEmpty
                            ? "This category has no tools."
                            : "Try a different search, or clear the filter."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    if !store.searchText.isEmpty {
                        Button("Clear search") { store.searchText = "" }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(store.filteredTools) { tool in
                            Button {
                                store.select(toolID: tool.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: tool.systemImage)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(tool.title)
                                            .font(.callout)
                                        Text(tool.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    store.selectedToolID == tool.id
                                        ? Color.accentColor.opacity(0.2)
                                        : .clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(.primary.opacity(0.025))
    }
}

private struct ToolWorkbenchView: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        let tool = store.selectedTool
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.title3.weight(.semibold))
                    Text(tool.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRunning {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel") { store.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    if tool.category == .sql || tool.id == "code.sqlFormat" {
                        Button("Load .sql") { loadSQLFileIntoEditor() }
                            .buttonStyle(.bordered)
                    }
                    Button("Clear") { store.clear() }
                        .buttonStyle(.bordered)
                    Button("Copy") { store.copyOutput() }
                        .buttonStyle(.bordered)
                        .disabled(store.output.isEmpty)
                    Button("Run") { store.run() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(12)

            Divider()

            GeometryReader { geo in
                VStack(spacing: 0) {
                    inputSection(tool)
                        .frame(height: max(180, geo.size.height * 0.45))
                    Divider()
                    outputSection
                        .frame(maxHeight: .infinity)
                }
            }

            if let meta = store.meta {
                HStack {
                    Text(meta)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func inputSection(_ tool: ToolDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !tool.optionKeys.isEmpty {
                optionsBar(tool)
            }
            if tool.showsPrimaryEditor || tool.showsSecondaryEditor {
                HStack(alignment: .top, spacing: 8) {
                    if tool.showsPrimaryEditor {
                        editor(label: tool.primaryLabel, text: $store.primaryInput)
                    }
                    if tool.showsSecondaryEditor, let secondary = tool.secondaryLabel {
                        editor(label: secondary, text: $store.secondaryInput)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else if tool.optionKeys.isEmpty {
                Text("Run to execute — no input required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            } else {
                Text("Configure options above, then Run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 10)
    }

    private func optionsBar(_ tool: ToolDefinition) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tool.optionKeys, id: \.self) { key in
                    HStack(spacing: 4) {
                        Text(key)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let choices = optionChoices(for: key, tool: tool), !choices.isEmpty {
                            Picker("", selection: pickerBinding(for: key, choices: choices)) {
                                ForEach(choices, id: \.self) { choice in
                                    Text(choice).tag(choice)
                                }
                            }
                            .labelsHidden()
                            .frame(width: optionWidth(for: key))
                            .controlSize(.small)
                        } else {
                            TextField(key, text: binding(for: key))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: optionWidth(for: key))
                                .font(.caption.monospaced())
                        }
                        if key == "dbPath" || key == "otherDbPath" || key == "sqlPath" {
                            Button("Browse") { pickSQLRelatedFile(into: key) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                        if key == "filePath" {
                            Button("Browse") { pickAnyFile(into: key) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(5)
                    .background(.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func editor(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body.monospaced())
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.previewHTML == nil ? "Output" : "Preview / Output")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = store.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let preview = store.previewHTML {
                HSplitView {
                    HTMLPreviewView(html: preview)
                        .frame(minWidth: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                        )
                    TextEditor(text: .constant(store.output))
                        .font(.body.monospaced())
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(minWidth: 180)
                }
            } else {
                TextEditor(text: .constant(store.output))
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { store.options[key] ?? "" },
            set: { store.options[key] = $0 }
        )
    }

    private func pickerBinding(for key: String, choices: [String]) -> Binding<String> {
        Binding(
            get: {
                let value = store.options[key] ?? ""
                return choices.contains(value) ? value : (choices.first ?? "")
            },
            set: { store.options[key] = $0 }
        )
    }

    private func optionWidth(for key: String) -> CGFloat {
        switch key {
        case "passphrase", "key", "signature", "target", "find", "replace", "format",
             "dbPath", "otherDbPath", "sqlPath", "filePath", "url", "filename", "description":
            return 180
        case "direction", "timezone", "from", "to", "algorithm", "charset", "language", "host",
             "justify", "align", "preset", "method", "freq":
            return 130
        default:
            return 88
        }
    }

    private func optionChoices(for key: String, tool: ToolDefinition) -> [String]? {
        switch key {
        case "mode":
            if tool.id.hasPrefix("enc.") { return ["encode", "decode"] }
            if tool.id == "crypto.bcrypt" || tool.id == "crypto.argon2" { return ["hash", "verify"] }
            if tool.id == "crypto.aes" || tool.id == "crypto.rsa" { return ["encrypt", "decrypt"] }
            if tool.id == "crypto.ecc" { return ["sign", "verify"] }
            if tool.id == "date.unix" { return ["to-date", "to-unix"] }
            if tool.id == "text.case" {
                return ["upper", "lower", "title", "camel", "snake", "kebab"]
            }
            return nil
        case "direction":
            if tool.id == "json.xml" { return ["xml-to-json", "json-to-xml"] }
            if tool.id == "json.yaml" { return ["yaml-to-json", "json-to-yaml"] }
            if tool.id == "json.toml" { return ["toml-to-json", "json-to-toml"] }
            if tool.id == "web.flexbox" {
                return ["row", "column", "row-reverse", "column-reverse"]
            }
            return nil
        case "public":
            return ["false", "true"]
        case "order":
            return ["asc", "desc"]
        case "charset":
            return ["all", "alpha", "alnum"]
        case "version":
            return ["4", "7"]
        case "unit":
            if tool.id == "date.epoch" { return ["ms", "s", "us", "ns"] }
            if tool.id == "date.relative" {
                return ["day", "hour", "minute", "week", "month", "year"]
            }
            return nil
        case "action":
            if tool.id == "code.snippets" { return ["list", "save", "load", "delete"] }
            if tool.id == "web.liveServer" || tool.id == "web.httpsServer" {
                return ["start", "stop"]
            }
            if tool.id == "date.stopwatch" { return ["lap", "reset"] }
            return nil
        case "algorithm":
            if tool.id == "crypto.fileHash" {
                return ["all", "md5", "sha1", "sha256", "sha512"]
            }
            if tool.id == "crypto.signature" { return ["ecdsa", "rsa"] }
            return nil
        case "language":
            return [
                "swift", "python", "javascript", "typescript", "json", "html", "css",
                "sql", "go", "rust", "java", "kotlin", "markdown", "yaml", "xml", "text", "auto",
            ]
        case "type":
            if tool.id == "net.dns" { return ["A", "AAAA", "CNAME", "MX", "TXT"] }
            if tool.id == "gen.cssGradient" { return ["linear", "radial"] }
            return nil
        case "justify":
            return ["flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly"]
        case "align":
            return ["stretch", "flex-start", "flex-end", "center", "baseline"]
        case "preset":
            return ["desktop", "mobile"]
        case "method":
            return ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
        case "freq":
            return ["DAILY", "WEEKLY", "MONTHLY", "YEARLY"]
        default:
            return nil
        }
    }

    private func pickSQLRelatedFile(into key: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        let sqlType = UTType(filenameExtension: "sql") ?? .plainText
        let dbTypes: [UTType] = [
            UTType(filenameExtension: "db") ?? .data,
            UTType(filenameExtension: "sqlite") ?? .data,
            UTType(filenameExtension: "sqlite3") ?? .data,
            .data,
        ]
        if key == "sqlPath" {
            panel.allowedContentTypes = [sqlType, .plainText]
        } else {
            panel.allowedContentTypes = dbTypes + [sqlType]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                store.options[key] = url.path
                if key == "sqlPath", url.pathExtension.lowercased() == "sql" {
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        store.primaryInput = text
                    }
                }
            }
        }
    }

    private func pickAnyFile(into key: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                store.options[key] = url.path
            }
        }
    }

    private func loadSQLFileIntoEditor() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sql") ?? .plainText,
            .plainText,
        ]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    store.primaryInput = text
                    store.options["sqlPath"] = url.path
                    store.errorMessage = nil
                } catch {
                    store.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct HTMLPreviewView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: URL(string: "https://toolbox.local/"))
    }
}
