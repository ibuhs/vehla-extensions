import AppKit
import MiniTerminalCore
import NotchKit
import SwiftUI

struct TerminalTabView: View {
    @ObservedObject var model: TerminalModel
    @State private var showHistory = false
    @State private var hoveringTop = false

    var body: some View {
        Group {
            if let session = model.active {
                content(session)
            } else {
                NKEmptyState("terminal", title: "Starting your shell…")
            }
        }
        // Tighter than the other tabs: the terminal needs every row it can get.
        .nkTab(horizontal: 24, top: 10, bottom: 8)
        .animation(.easeOut(duration: 0.12), value: showHistory)
        .animation(.easeOut(duration: 0.15), value: hoveringTop)
        .onChange(of: showHistory) { _, shown in if !shown { model.refocus() } }
    }

    @ViewBuilder private func content(_ session: TerminalSession) -> some View {
        let autoHide = model.autoHideHeader
        let barVisible = !autoHide || hoveringTop || showHistory || session.running != nil || model.status != nil
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if !autoHide { SessionBar(model: model, session: session, showHistory: $showHistory) }
                ZStack {
                    TerminalRepresentable(session: session, theme: model.theme, fontSize: CGFloat(model.fontSize),
                                          focusToken: model.focusToken)
                        .id(session.id)
                    if showHistory {
                        HistoryPanel(model: model, isPresented: $showHistory)
                            .padding(.top, autoHide ? 26 : 0)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if autoHide {
                // The bar floats over the terminal and only appears when you reach for it.
                SessionBar(model: model, session: session, showHistory: $showHistory)
                    .padding(.vertical, 2)
                    .background(LinearGradient(colors: [.black.opacity(0.96), .black.opacity(0.9), .clear],
                                               startPoint: .top, endPoint: .bottom))
                    .opacity(barVisible ? 1 : 0)
                    .allowsHitTesting(barVisible)
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hoveringTop = point.y < 30
            case .ended: hoveringTop = false
            }
        }
    }
}

// MARK: - Terminal

private struct TerminalRepresentable: NSViewRepresentable {
    let session: TerminalSession
    let theme: TerminalTheme
    let fontSize: CGFloat
    let focusToken: Int

    final class Coordinator { var focusToken = -1 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(frame: .zero)
        view.theme = theme
        view.fontSize = fontSize
        view.session = session
        return view
    }

    func updateNSView(_ view: TerminalNSView, context: Context) {
        if view.session !== session { view.session = session }
        if view.theme != theme { view.theme = theme }
        if view.fontSize != fontSize { view.fontSize = fontSize }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            view.focus()
        }
    }
}

// MARK: - Header

private struct SessionBar: View {
    @ObservedObject var model: TerminalModel
    @ObservedObject var session: TerminalSession
    @Binding var showHistory: Bool

    var body: some View {
        HStack(spacing: 6) {
            sessionPills
            context.frame(maxWidth: .infinity, alignment: .leading)
            if let status = model.status {
                Text(status).font(NK.Font.caption).foregroundStyle(NK.Palette.secondary).lineLimit(1)
            } else {
                resultChip
            }
            favoritesMenu
            quickMenu
            NKIconButton("clock.arrow.circlepath", help: "Command history", size: 20) { showHistory.toggle() }
            NKIconButton("doc.on.doc", help: "Copy the last command's output", size: 20) { model.copyLastOutput() }
            moreMenu
        }
        .frame(height: 22)
    }

    // MARK: Sessions and context

    private var sessionPills: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, s in
                let selected = s.id == session.id
                Button { model.select(s) } label: {
                    Text("\(index + 1)").font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 19, height: 19)
                        .background(Circle().fill(selected ? Color.white.opacity(0.92) : NK.Palette.surface))
                        .foregroundStyle(selected ? Color.black : NK.Palette.secondary)
                        .overlay(alignment: .topTrailing) {
                            if s.running != nil { Circle().fill(Color.white).frame(width: 5, height: 5).offset(x: 1, y: -1) }
                        }
                }
                .buttonStyle(.plain)
                .help(index == 0 ? "Session 1" : "Session \(index + 1) · \(TerminalModel.shortPath(s.cwd))")
            }
            if model.sessions.count < TerminalModel.maxSessions {
                NKIconButton("plus", help: "New session in this folder", size: 19) { model.newSession() }
            }
        }
    }

    @ViewBuilder private var context: some View {
        if let run = session.running {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(run.command).font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(TerminalModel.duration(ctx.date.timeIntervalSince(run.startedAt)))
                        .font(NK.Font.caption.monospacedDigit()).foregroundStyle(NK.Palette.secondary)
                }
                Button { session.interrupt() } label: {
                    Label("Stop", systemImage: "stop.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(NKPillButtonStyle(.light)).fixedSize()
                .help("Interrupt (Ctrl-C)")
            }
            .padding(.leading, 4)
        } else {
            Button { model.revealCwd() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                    // The real path, with ~ for home; a long one is shortened in the middle.
                    Text(TerminalModel.tildePath(session.cwd))
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(NK.Palette.secondary)
                .padding(.horizontal, 8).frame(height: 20)
                .background(Capsule().fill(NK.Palette.surface))
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .help(TerminalModel.tildePath(session.cwd) + " · click to show in Finder")
        }
    }

    @ViewBuilder private var resultChip: some View {
        if let result = session.lastResult {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if ctx.date.timeIntervalSince(result.finishedAt) < 12, session.running == nil {
                    let ok = result.exitCode == 0
                    NKChip("\(ok ? "✓" : "✗") \(result.exitCode.map { $0 == 0 ? "" : "\($0) · " } ?? "")\(TerminalModel.duration(result.duration))")
                        .help(result.command)
                }
            }
        }
    }

    // MARK: Menus

    private var favoritesMenu: some View {
        let favorites = model.favoriteFolders
        return Menu {
            if favorites.isEmpty {
                Text("No favorite folders yet")
            } else {
                Section("Go to") {
                    ForEach(favorites) { f in
                        Button { model.go(to: f) } label: {
                            Label("\(f.name)   \(TerminalModel.shortPath(f.path))",
                                  systemImage: FavoriteFolders.contains(session.cwd, in: [f]) ? "checkmark" : "folder")
                        }
                    }
                }
                if model.sessions.count < TerminalModel.maxSessions {
                    Menu("Open in a new session") {
                        ForEach(favorites) { f in Button(f.name) { model.go(to: f, newSession: true) } }
                    }
                }
            }
            Divider()
            Button(model.currentIsFavorite ? "Remove this folder from favorites" : "Add this folder to favorites") {
                model.toggleCurrentFavorite()
            }
            if !favorites.isEmpty {
                Menu("Remove") {
                    ForEach(favorites) { f in Button(f.name) { model.removeFavorite(f) } }
                }
                Button("Rename favorites…") { model.revealPrefs() }
            }
        } label: { iconLabel(model.currentIsFavorite ? "star.fill" : "star") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Favorite folders")
    }

    private var quickMenu: some View {
        Menu {
            let pinned = model.history.pinned
            if !pinned.isEmpty {
                Section("Pinned") { ForEach(pinned) { e in Button(TerminalModel.cut(e.command, 50)) { model.run(e.command) } } }
            }
            let frequent = model.history.frequent(limit: 4).filter { c in !pinned.contains { $0.command == c } }
            if !frequent.isEmpty {
                Section("Frequent") { ForEach(frequent, id: \.self) { c in Button(TerminalModel.cut(c, 50)) { model.run(c) } } }
            }
            Section("Quick commands") {
                ForEach(model.quickCommands) { q in Button(q.title) { model.run(q.command) } }
            }
            Divider()
            Button("Edit quick commands…") { model.revealPrefs() }
        } label: { iconLabel("bolt.fill") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Quick commands")
    }

    private var moreMenu: some View {
        Menu {
            Button("Paste") { model.pasteFromClipboard() }
            Divider()
            Menu("Theme") {
                ForEach(TerminalTheme.all) { theme in
                    Button { model.setTheme(theme) } label: {
                        if theme.id == model.theme.id { Label(theme.name, systemImage: "checkmark") } else { Text(theme.name) }
                    }
                }
            }
            Button("Larger text") { model.adjustFont(by: 1) }
            Button("Smaller text") { model.adjustFont(by: -1) }
            Toggle("Minimal prompt (just % and the cursor)", isOn: Binding(get: { model.minimalPrompt }, set: { model.setMinimalPrompt($0) }))
            Toggle("Auto-hide this bar for more room", isOn: Binding(get: { model.autoHideHeader }, set: { model.setAutoHideHeader($0) }))
            Toggle("Show running commands in the closed Notch", isOn: Binding(get: { model.showRunning }, set: { model.setShowRunning($0) }))
            Divider()
            Button("Clear screen") { session.clear() }
            if model.sessions.count < TerminalModel.maxSessions { Button("New session") { model.newSession() } }
            if model.sessions.count > 1 { Button("Close this session") { model.close(session) } }
            Divider()
            Button("Clear history (keep pinned)") { model.clearUnpinnedHistory() }
        } label: { iconLabel("ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More")
    }

    private func iconLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(NK.Palette.primary)
            .frame(width: 20, height: 20)
            .background(Circle().fill(NK.Palette.surface))
    }
}

// MARK: - History

private struct HistoryPanel: View {
    @ObservedObject var model: TerminalModel
    @Binding var isPresented: Bool
    @State private var query = ""
    @FocusState private var searching: Bool

    private var results: [HistoryEntry] {
        let all = model.history.search(query)
        guard query.trimmingCharacters(in: .whitespaces).isEmpty else { return all }
        return all.filter(\.pinned) + all.filter { !$0.pinned }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(NK.Palette.tertiary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.plain).font(NK.Font.body)
                    .focused($searching)
                    .onSubmit { if let first = results.first { choose(first, run: false) } }
                Text("\(model.history.entries.count)").font(NK.Font.caption.monospacedDigit()).foregroundStyle(NK.Palette.tertiary)
                NKIconButton("xmark", help: "Close history", size: 20) { isPresented = false }
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(NK.Palette.surfaceRaised))

            if results.isEmpty {
                NKEmptyState("clock.arrow.circlepath", title: query.isEmpty ? "No history yet" : "No matches",
                             message: query.isEmpty ? "Commands you run show up here, with results and timings." : nil)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            HistoryRow(entry: entry, model: model, choose: choose)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(NK.Palette.stroke, lineWidth: 1))
        .onAppear { searching = true }
        .onExitCommand { isPresented = false }
    }

    private func choose(_ entry: HistoryEntry, run: Bool) {
        if run { model.run(entry.command) } else { model.insert(entry.command) }
        isPresented = false
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    @ObservedObject var model: TerminalModel
    let choose: (HistoryEntry, Bool) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph).font(.system(size: 9, weight: .bold))
                .foregroundStyle(entry.succeeded == false ? NK.Palette.primary : NK.Palette.tertiary)
                .frame(width: 12)
                .help(entry.exitCode.map { "Exit status \($0)" } ?? "")
            Text(entry.command).font(.system(size: 11, design: .monospaced)).lineLimit(1)
            if entry.runs > 1 { NKChip("×\(entry.runs)") }
            Spacer(minLength: 6)
            if hovering {
                HStack(spacing: 4) {
                    NKIconButton("arrow.down.left", help: "Put on the prompt", size: 20) { choose(entry, false) }
                    NKIconButton("play.fill", help: "Run", size: 20) { choose(entry, true) }
                    NKIconButton(entry.pinned ? "pin.slash" : "pin", help: entry.pinned ? "Unpin" : "Pin", size: 20) { model.togglePin(entry) }
                    NKIconButton("trash", help: "Remove", size: 20) { model.removeHistory(entry) }
                }
            } else {
                if let cwd = entry.cwd {
                    Text(TerminalModel.shortPath(cwd)).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(NK.Palette.tertiary).lineLimit(1)
                }
                Text(TerminalModel.duration(entry.duration)).font(NK.Font.caption.monospacedDigit()).foregroundStyle(NK.Palette.tertiary)
                Text(entry.date, style: .relative).font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? NK.Palette.surface : .clear))
        .contentShape(Rectangle())
        .onTapGesture { choose(entry, false) }
        .onHover { hovering = $0 }
        .accessibilityLabel(entry.command)
    }

    private var glyph: String {
        if entry.pinned { return "pin.fill" }
        switch entry.succeeded {
        case .some(true): return "checkmark"
        case .some(false): return "xmark"
        case .none: return "circle.fill"
        }
    }
}
