import AppKit
import SwiftUI
import VehlaNativeUISDK

@MainActor
final class ZLibraryStore: ObservableObject {
    @Published var mode: ZLibraryMode
    @Published var query = ""
    @Published private(set) var books: [ZLibraryBook] = []
    @Published private(set) var queue: [ZLibraryQueueItem] = []
    @Published private(set) var selectedIDs: Set<String> = []
    @Published private(set) var downloadingIDs: Set<String> = []
    @Published private(set) var isSearching = false
    @Published private(set) var cliAvailable = false
    @Published var settings = ZLibrarySettings()
    @Published var showingSettings = false
    @Published var errorMessage: String?

    let context: VehlaWorkspaceContext
    private let persistence: ZLibraryPersistence
    private var searchTask: Task<Void, Never>?

    init(context: VehlaWorkspaceContext) {
        self.context = context
        persistence = ZLibraryPersistence(directory: context.dataDirectory)
        mode = context.launchRequest.commandID == "download-queue" ? .queue : .search
        query = context.launchRequest.query

        Task {
            let state = await persistence.load()
            settings = state.settings
            queue = state.queue
            await refreshCLIAvailability()
            if !query.isEmpty { search() }
        }
    }

    deinit {
        searchTask?.cancel()
    }

    var selectedBooks: [ZLibraryBook] {
        books.filter { selectedIDs.contains($0.id) }
    }

    var pendingQueue: [ZLibraryQueueItem] {
        queue.filter { !$0.downloaded }
    }

    var downloadedQueue: [ZLibraryQueueItem] {
        queue.filter(\.downloaded)
    }

    func search() {
        searchTask?.cancel()
        let requestedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedQuery.isEmpty else {
            books = []
            isSearching = false
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                let results = try await ZLibraryCLI.shared.search(
                    requestedQuery,
                    settings: settings
                )
                guard !Task.isCancelled, query.trimmingCharacters(in: .whitespacesAndNewlines) == requestedQuery else {
                    return
                }
                books = results
                cliAvailable = true
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                books = []
                errorMessage = error.localizedDescription
                await refreshCLIAvailability()
            }
        }
    }

    func toggleSelection(_ book: ZLibraryBook) {
        if selectedIDs.contains(book.id) {
            selectedIDs.remove(book.id)
        } else {
            selectedIDs.insert(book.id)
        }
    }

    func toggleQueue(_ book: ZLibraryBook) {
        if queue.contains(where: { $0.id == book.id }) {
            queue.removeAll { $0.id == book.id }
            context.showMessage("Removed \(book.name) from the queue.")
        } else {
            queue.append(
                ZLibraryQueueItem(book: book, downloaded: false, queuedAt: .now)
            )
            context.showMessage("Added \(book.name) to the queue.")
        }
        persist()
    }

    func removeFromQueue(_ item: ZLibraryQueueItem) {
        queue.removeAll { $0.id == item.id }
        persist()
    }

    func clearDownloaded() {
        queue.removeAll(where: \.downloaded)
        persist()
    }

    func download(_ book: ZLibraryBook) {
        guard !downloadingIDs.contains(book.id) else { return }
        downloadingIDs.insert(book.id)
        Task {
            defer { downloadingIDs.remove(book.id) }
            do {
                try await ZLibraryCLI.shared.download(book, settings: settings)
                markDownloaded(book.id)
                context.showMessage("Downloaded \(book.name).")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func downloadSelected() {
        let selected = selectedBooks
        guard !selected.isEmpty else { return }
        Task {
            var failed = Set<String>()
            for book in selected {
                downloadingIDs.insert(book.id)
                do {
                    try await ZLibraryCLI.shared.download(book, settings: settings)
                    markDownloaded(book.id)
                } catch {
                    failed.insert(book.id)
                    errorMessage = error.localizedDescription
                }
                downloadingIDs.remove(book.id)
            }
            selectedIDs = failed
            if failed.isEmpty {
                context.showMessage("Downloaded \(selected.count) books.")
            }
        }
    }

    func downloadPending() {
        let pending = pendingQueue.map(\.book)
        guard !pending.isEmpty else { return }
        Task {
            var succeeded = 0
            for book in pending {
                downloadingIDs.insert(book.id)
                do {
                    try await ZLibraryCLI.shared.download(book, settings: settings)
                    markDownloaded(book.id)
                    succeeded += 1
                } catch {
                    errorMessage = error.localizedDescription
                }
                downloadingIDs.remove(book.id)
            }
            context.showMessage("Downloaded \(succeeded) of \(pending.count) queued books.")
        }
    }

    func saveSettings() {
        showingSettings = false
        persist()
        Task {
            await refreshCLIAvailability()
            if !query.isEmpty { search() }
        }
    }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Directory"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(
            fileURLWithPath: NSString(string: settings.downloadDirectory).expandingTildeInPath
        )
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectory = url.path
        }
    }

    func copyID(_ book: ZLibraryBook) {
        context.copyText(book.id)
        context.showMessage("Copied book ID.")
    }

    func openInBrowser(_ book: ZLibraryBook) {
        guard let url = book.webpageURL else { return }
        context.open(url)
    }

    func isQueued(_ book: ZLibraryBook) -> Bool {
        queue.contains { $0.id == book.id }
    }

    private func markDownloaded(_ id: String) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue[index].downloaded = true
        }
        persist()
    }

    private func persist() {
        let state = ZLibrarySavedState(settings: settings, queue: queue)
        Task {
            do {
                try await persistence.save(state)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Could not save the Z-Library queue."
                }
            }
        }
    }

    private func refreshCLIAvailability() async {
        cliAvailable = await ZLibraryCLI.shared.isAvailable(settings: settings)
    }
}

struct ZLibraryView: View {
    @ObservedObject var store: ZLibraryStore
    @ObservedObject var theme: ZLibraryThemeCoordinator

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            if store.mode == .search {
                searchSurface
            } else {
                queueSurface
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .background(Color(nsColor: theme.theme.backgroundColor).opacity(0.94))
        .foregroundStyle(Color(nsColor: theme.theme.primaryTextColor))
        .preferredColorScheme(theme.theme.isDark ? .dark : .light)
        .sheet(isPresented: $store.showingSettings) {
            ZLibrarySettingsView(store: store, theme: theme)
        }
        .alert(
            "Z-Library",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("View", selection: $store.mode) {
                Label("Search", systemImage: "magnifyingglass").tag(ZLibraryMode.search)
                Label("Queue \(store.pendingQueue.count)", systemImage: "tray.full").tag(ZLibraryMode.queue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)

            Spacer()

            if store.mode == .search, !store.selectedIDs.isEmpty {
                Button {
                    store.downloadSelected()
                } label: {
                    Label("Download \(store.selectedIDs.count)", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            } else if store.mode == .queue, !store.pendingQueue.isEmpty {
                Button {
                    store.downloadPending()
                } label: {
                    Label("Download All", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            Circle()
                .fill(store.cliAvailable ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .help(store.cliAvailable ? "zlib CLI is ready" : "zlib CLI needs setup")

            Button {
                store.showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Z-Library settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var searchSurface: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search by title, author, ISBN, or keyword", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: store.query) { _, _ in store.search() }
                    .onSubmit { store.search() }
                if store.isSearching {
                    ProgressView().controlSize(.small)
                } else if !store.query.isEmpty {
                    Button {
                        store.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 17)
            .frame(height: 54)
            Divider().opacity(0.14)

            if !store.cliAvailable {
                setupState
            } else if store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState(
                    symbol: "books.vertical",
                    title: "Search Z-Library",
                    message: "Type a title, author, ISBN, or keyword."
                )
            } else if !store.isSearching && store.books.isEmpty {
                emptyState(
                    symbol: "book.closed",
                    title: "No books found",
                    message: "Try a broader or differently spelled search."
                )
            } else {
                bookList(store.books)
            }
        }
    }

    private var queueSurface: some View {
        Group {
            if store.queue.isEmpty {
                emptyState(
                    symbol: "tray",
                    title: "Queue is empty",
                    message: "Bookmark books from Search to save them for later."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                        if !store.pendingQueue.isEmpty {
                            Section {
                                ForEach(store.pendingQueue) { item in
                                    queueRow(item)
                                }
                            } header: {
                                sectionHeader("Queued", count: store.pendingQueue.count)
                            }
                        }
                        if !store.downloadedQueue.isEmpty {
                            Section {
                                ForEach(store.downloadedQueue) { item in
                                    queueRow(item)
                                }
                            } header: {
                                sectionHeader("Downloaded", count: store.downloadedQueue.count)
                            }
                            Button("Clear Downloaded", role: .destructive) {
                                store.clearDownloaded()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.top, 5)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func bookList(_ books: [ZLibraryBook]) -> some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(books) { book in
                    ZLibraryBookRow(
                        book: book,
                        selected: store.selectedIDs.contains(book.id),
                        queued: store.isQueued(book),
                        downloaded: false,
                        downloading: store.downloadingIDs.contains(book.id),
                        onDownload: { store.download(book) },
                        onSelect: { store.toggleSelection(book) },
                        onQueue: { store.toggleQueue(book) },
                        onOpen: { store.openInBrowser(book) },
                        onCopyID: { store.copyID(book) },
                        onRemove: nil
                    )
                }
            }
            .padding(14)
        }
    }

    private func queueRow(_ item: ZLibraryQueueItem) -> some View {
        ZLibraryBookRow(
            book: item.book,
            selected: false,
            queued: true,
            downloaded: item.downloaded,
            downloading: store.downloadingIDs.contains(item.id),
            onDownload: { store.download(item.book) },
            onSelect: nil,
            onQueue: nil,
            onOpen: { store.openInBrowser(item.book) },
            onCopyID: { store.copyID(item.book) },
            onRemove: { store.removeFromQueue(item) }
        )
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title).font(.headline)
            Text("\(count)").foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 7)
        .background(Color(nsColor: theme.theme.backgroundColor).opacity(0.96))
    }

    private var setupState: some View {
        VStack(spacing: 11) {
            Image(systemName: "terminal")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Set up the zlib CLI").font(.headline)
            Text("Install it with `brew install heartleo/tap/zlib`, run `zlib login` in Terminal, then confirm or choose its path in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button("Open Settings") { store.showingSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private func emptyState(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(Color(nsColor: theme.theme.accentColor))
            Text(title).font(.headline)
            Text(message).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct ZLibraryBookRow: View {
    let book: ZLibraryBook
    let selected: Bool
    let queued: Bool
    let downloaded: Bool
    let downloading: Bool
    let onDownload: () -> Void
    let onSelect: (() -> Void)?
    let onQueue: (() -> Void)?
    let onOpen: () -> Void
    let onCopyID: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: downloaded ? "checkmark.circle.fill" : selected ? "checkmark.circle.fill" : "book.closed")
                .font(.title3)
                .foregroundStyle(downloaded ? .green : selected ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 7) {
                    if !book.authorLine.isEmpty {
                        Text(book.authorLine).lineLimit(1)
                    }
                    metadata
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if downloading {
                ProgressView().controlSize(.small)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .help(downloaded ? "Download again" : "Download")
            }

            if let onSelect {
                Button(action: onSelect) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .help(selected ? "Deselect" : "Select for bulk download")
            }

            if let onQueue {
                Button(action: onQueue) {
                    Image(systemName: queued ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.plain)
                .help(queued ? "Remove from queue" : "Add to queue")
            }

            Menu {
                if book.webpageURL != nil {
                    Button("Open in Browser", action: onOpen)
                }
                Button("Copy Book ID", action: onCopyID)
                if let onRemove {
                    Divider()
                    Button("Remove from Queue", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var metadata: some View {
        HStack(spacing: 6) {
            if let value = book.extensionName, !value.isEmpty {
                Text(value.uppercased())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.09))
                    .clipShape(Capsule())
            }
            if let value = book.size, !value.isEmpty { Text(value) }
            if let value = book.year, !value.isEmpty { Text(value) }
            if let value = book.rating, !value.isEmpty {
                Label(value, systemImage: "star.fill")
            }
        }
    }
}

private struct ZLibrarySettingsView: View {
    @ObservedObject var store: ZLibraryStore
    @ObservedObject var theme: ZLibraryThemeCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("Z-Library Settings")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("zlib Binary Path").font(.headline)
                TextField("Auto-detect Homebrew installation", text: $store.settings.binaryPath)
                    .textFieldStyle(.roundedBorder)
                Text("Leave blank to check /opt/homebrew/bin, /usr/local/bin, ~/.local/bin, and PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Download Directory").font(.headline)
                HStack {
                    TextField("~/Downloads", text: $store.settings.downloadDirectory)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…") { store.chooseDownloadDirectory() }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Domain Override").font(.headline)
                TextField("Optional Z-Library domain", text: $store.settings.domainOverride)
                    .textFieldStyle(.roundedBorder)
                Text("Only set this when `zlib doctor --eapi` recommends a healthy domain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Install with `brew install heartleo/tap/zlib`, then run `zlib login` in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { store.showingSettings = false }
                Button("Save") { store.saveSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Color(nsColor: theme.theme.surfaceColor))
    }
}
