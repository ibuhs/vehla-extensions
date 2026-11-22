import AppKit
import SwiftUI
import VehlaNotchSDK

// MARK: - Model (owned by the plugin so results survive tab view-controller releases)

@MainActor
final class WallhavenModel: ObservableObject {
    @Published var query = WallhavenQuery()
    @Published var wallpapers: [Wallpaper] = []
    @Published var lastPage = 1
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selected: Wallpaper? {
        didSet {
            if let selected { lastViewedID = selected.id } else { PreviewController.shared.close() }
            saveSession()
        }
    }
    /// The last image you opened; the grid scrolls back to it.
    @Published private(set) var lastViewedID: String?
    @Published var statusMessage: String?
    @Published var favorites: [Wallpaper] = []
    @Published var showingFavorites = false { didSet { saveSession() } }
    /// Sketchy and NSFW results need an API key, so the content filter only appears when one is set.
    @Published private(set) var hasAPIKey = false

    /// What the grid shows: saved favorites, or the current search results.
    var visible: [Wallpaper] { showingFavorites ? favorites : wallpapers }

    private var notch: VehlaNotch?
    private let client = WallhavenClient()
    private var loadTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var hasLoaded = false
    private var restoring = false
    /// Large previews, so going back and forth between neighbours is instant. Emptied when the preview closes.
    private var fullImages = RecentImages<String>(limit: 2)
    private var releaseTask: Task<Void, Never>?

    func attach(_ notch: VehlaNotch) {
        self.notch = notch
        let key = notch.secret(named: "apiKey")
        hasAPIKey = !(key ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        Task { await client.setAPIKey(key) }
        loadPersisted()
        if !hasAPIKey { query.tier = .regular }
        restoreSession()
    }

    // MARK: Persistence (favorites and preferences live in the extension's data folder)

    private struct Prefs: Codable {
        var minResolution: MinResolution
        var tier: Int?
        /// Only read: the earlier multi-select version saved a bit mask here.
        var purity: Int?
    }

    private var favoritesURL: URL? { notch?.dataDirectory.appendingPathComponent("favorites.json") }
    private var prefsURL: URL? { notch?.dataDirectory.appendingPathComponent("prefs.json") }

    private func loadPersisted() {
        let decoder = JSONDecoder()
        if let url = favoritesURL, let data = try? Data(contentsOf: url),
           let saved = try? decoder.decode([Wallpaper].self, from: data) {
            favorites = saved
        }
        if let url = prefsURL, let data = try? Data(contentsOf: url),
           let prefs = try? decoder.decode(Prefs.self, from: data) {
            query.minResolution = prefs.minResolution
            if let raw = prefs.tier, let tier = PurityTier(rawValue: raw) { query.tier = tier }
            else if let mask = prefs.purity, mask != 0 { query.tier = PurityTier(legacyMask: mask) }
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    func isFavorite(_ wallpaper: Wallpaper) -> Bool {
        favorites.contains { $0.id == wallpaper.id }
    }

    func toggleFavorite(_ wallpaper: Wallpaper) {
        if let index = favorites.firstIndex(where: { $0.id == wallpaper.id }) {
            favorites.remove(at: index)
            flash("Removed from favorites")
        } else {
            favorites.insert(wallpaper, at: 0)
            flash("Added to favorites")
        }
        write(favorites, to: favoritesURL)
    }

    func setMinResolution(_ value: MinResolution) {
        guard value != query.minResolution else { return }
        query.minResolution = value
        savePrefs()
        showingFavorites = false
        query.page = 1
        query.seed = nil
        load()
    }

    private func savePrefs() {
        write(Prefs(minResolution: query.minResolution, tier: query.tier.rawValue, purity: nil), to: prefsURL)
    }

    /// Picks the content tier (Regular, Sketchy or NSFW). Needs an API key; Regular is the default.
    func setTier(_ tier: PurityTier) {
        guard hasAPIKey, tier != query.tier else { return }
        query.tier = tier
        savePrefs()
        showingFavorites = false
        query.page = 1
        query.seed = nil
        load()
    }

    // MARK: Where you left off

    private var sessionURL: URL? { notch?.dataDirectory.appendingPathComponent("session.json") }

    func saveSession() {
        guard !restoring, notch != nil else { return }
        write(SessionState(text: query.text, sorting: query.sorting.rawValue, page: query.page, seed: query.seed,
                           selected: selected, showingFavorites: showingFavorites, lastViewedID: lastViewedID),
              to: sessionURL)
    }

    private func restoreSession() {
        guard let url = sessionURL, let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(SessionState.self, from: data) else { return }
        restoring = true
        defer { restoring = false }
        query.text = state.text
        query.sorting = WallhavenSorting(rawValue: state.sorting) ?? .toplist
        query.page = max(1, state.page)
        query.seed = state.seed
        showingFavorites = state.showingFavorites
        lastViewedID = state.lastViewedID
        selected = state.selected
    }

    // MARK: Preview

    func togglePreview(_ wallpaper: Wallpaper) {
        if PreviewController.shared.isShowing { PreviewController.shared.close() }
        else { PreviewController.shared.show(wallpaper, model: self) }
    }

    /// Left/right in the large preview: move to the neighbouring wallpaper in the current grid.
    func selectNeighbor(_ offset: Int) {
        guard let current = selected, let i = visible.firstIndex(where: { $0.id == current.id }),
              visible.indices.contains(i + offset) else { return }
        let next = visible[i + offset]
        selected = next
        PreviewController.shared.update(next, model: self)
    }

    /// The wallpaper at the size the preview shows it (`maxPixel` on its longest side).
    func loadFullImage(_ wallpaper: Wallpaper, maxPixel: Int) async -> NSImage? {
        let key = "\(wallpaper.id)@\(maxPixel)"
        if let cached = fullImages.image(for: key) { return cached }
        guard let file = try? await client.downloadImage(from: wallpaper.path) else { return nil }
        defer { try? FileManager.default.removeItem(at: file) }
        guard !Task.isCancelled else { return nil }
        let decoded = await Task.detached(priority: .userInitiated) {
            ImageDecoder.downsample(contentsOf: file, maxPixel: maxPixel)
        }.value
        guard let decoded, !Task.isCancelled else { return nil }
        let image = NSImage(cgImage: decoded, size: .zero)
        fullImages.store(image, for: key)
        return image
    }

    func releaseFullImages() {
        fullImages.removeAll()
        MemoryRelief.schedule()
    }

    /// Thumbnails are kept for a moment so reopening the Notch is instant, then let go.
    func tabVisibilityChanged(_ visible: Bool) {
        releaseTask?.cancel()
        releaseTask = nil
        if visible { startIfNeeded(); return }
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            ThumbnailCache.shared.removeAll()
            MemoryRelief.schedule()
        }
    }

    func detach() {
        PreviewController.shared.close()
        releaseTask?.cancel()
        fullImages.removeAll()
        ThumbnailCache.shared.removeAll()
        loadTask?.cancel()
        statusTask?.cancel()
        notch = nil
    }

    func startIfNeeded() { if !hasLoaded && !isLoading { load() } }

    func search(text: String, sorting: WallhavenSorting) {
        showingFavorites = false
        query.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query.sorting = sorting
        query.page = 1
        query.seed = nil
        load()
        saveSession()
    }

    func goToPage(_ page: Int) {
        guard page >= 1, page <= lastPage, page != query.page else { return }
        query.page = page
        load()
        saveSession()
    }

    func load() {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        let query = self.query
        loadTask = Task { [client] in
            do {
                let page = try await client.search(query)
                try Task.checkCancellation()
                if page.data.isEmpty, query.page > 1 {
                    // A saved page that no longer exists (results shrank): start from the first page.
                    self.query.page = 1
                    self.load()
                    return
                }
                self.wallpapers = page.data
                self.lastPage = max(page.meta.lastPage, 1)
                self.query.seed = page.meta.seed
                self.hasLoaded = true
                self.isLoading = false
                self.errorMessage = nil
                self.saveSession()
            } catch is CancellationError {
                return
            } catch {
                // A superseded request surfaces as URLError.cancelled; it is not a failure.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func loadThumbnail(_ url: URL) async -> NSImage? {
        if let cached = ThumbnailCache.shared.image(for: url) { return cached }
        guard let data = try? await client.imageData(from: url),
              let image = NSImage(data: data) else { return nil }
        ThumbnailCache.shared.store(image, for: url)
        return image
    }

    // MARK: Actions

    func setDesktop(_ wallpaper: Wallpaper) {
        guard let notch else { return }
        let directory = notch.dataDirectory
        flash("Downloading…")
        notch.show(VehlaNotchActivity(
            id: "wallpaper", systemImage: "arrow.down.circle", title: "Wallpaper",
            detail: wallpaper.resolution, duration: 60
        ))
        Task {
            do {
                try await WallpaperInstaller.setDesktop(wallpaper, client: client, directory: directory)
                flash("Wallpaper set")
                notch.show(VehlaNotchActivity(
                    id: "wallpaper", systemImage: "checkmark.circle.fill", title: "Wallpaper set",
                    detail: wallpaper.resolution, tintHex: "#34C759", duration: 4
                ))
            } catch {
                flash(error.localizedDescription)
                notch.end("wallpaper")
            }
        }
    }

    func openOnWeb(_ wallpaper: Wallpaper) { notch?.open(wallpaper.url) }

    func copyLink(_ wallpaper: Wallpaper) {
        let ok = notch?.copy(wallpaper.url.absoluteString) ?? false
        flash(ok ? "Link copied" : "Clipboard not allowed")
    }

    private func flash(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.statusMessage = nil }
        }
    }
}

// MARK: - Plugin

@objc(WallhavenNotchPlugin)
public final class WallhavenNotchPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = WallhavenModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) {
        model.attach(VehlaNotch(host))
    }

    @MainActor
    public func notchWillStop() { model.detach() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "wallhaven" else { return nil }
        model.tabVisibilityChanged(true)
        return NSHostingController(rootView: WallhavenTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) {
        guard tabID == "wallhaven" else { return }
        model.tabVisibilityChanged(isVisible)
    }
}

// MARK: - Views (the Notch is always dark)

/// A fixed 16:10 cell: the image fills and is cropped to it, so every cell is the same size.
struct RemoteThumb: View {
    let url: URL
    @ObservedObject var model: WallhavenModel
    @State private var image: NSImage?

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(1.6, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
            .task(id: url) {
                let loaded = await model.loadThumbnail(url)
                if Task.isCancelled { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }
}

private struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(prominent ? Color.accentColor : Color.white.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct RoundIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct ThumbCell: View {
    let wallpaper: Wallpaper
    @ObservedObject var model: WallhavenModel
    @State private var hovering = false

    var body: some View {
        Button { model.selected = wallpaper } label: {
            RemoteThumb(url: wallpaper.thumbs.large, model: model)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if model.isFavorite(wallpaper) || hovering {
                        Button { model.toggleFavorite(wallpaper) } label: {
                            Image(systemName: model.isFavorite(wallpaper) ? "heart.fill" : "heart")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(model.isFavorite(wallpaper) ? Color.pink : .white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .help(model.isFavorite(wallpaper) ? "Remove from favorites" : "Add to favorites")
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text(wallpaper.resolution)
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.85 : 0.1), lineWidth: hovering ? 2 : 1)
                )
                .scaleEffect(hovering ? 1.02 : 1)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Wallpaper \(wallpaper.id), \(wallpaper.resolution)")
    }
}

struct WallhavenTabView: View {
    @ObservedObject var model: WallhavenModel
    @State private var text: String
    @State private var sorting: WallhavenSorting
    @State private var restoredScroll = false

    init(model: WallhavenModel) {
        self.model = model
        _text = State(initialValue: model.query.text)
        _sorting = State(initialValue: model.query.sorting)
    }

    var body: some View {
        Group {
            if let wallpaper = model.selected {
                DetailView(wallpaper: wallpaper, model: model)
            } else {
                browser
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // The Notch gives a tab roughly 160pt of height: one control row plus a scrolling grid.
    private var browser: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Search Wallhaven", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .onSubmit { model.search(text: text, sorting: sorting) }
                    if !text.isEmpty {
                        Button {
                            text = ""
                            model.search(text: "", sorting: sorting)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.1)))

                Menu {
                    ForEach(WallhavenSorting.allCases) { option in
                        Button(option.title) {
                            sorting = option
                            model.search(text: text, sorting: option)
                        }
                    }
                } label: {
                    Text(sorting.title).font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .fixedSize()

                Menu {
                    ForEach(MinResolution.allCases) { option in
                        Button {
                            model.setMinResolution(option)
                        } label: {
                            if option == model.query.minResolution {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                } label: {
                    Label(model.query.minResolution.title, systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
                .help("Minimum resolution")

                if model.hasAPIKey {
                    Menu {
                        ForEach(PurityTier.allCases) { tier in
                            Button {
                                model.setTier(tier)
                            } label: {
                                if tier == model.query.tier { Label(tier.title, systemImage: "checkmark") }
                                else { Text(tier.title) }
                            }
                        }
                    } label: {
                        Label(model.query.tier.title, systemImage: "shield.lefthalf.filled")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.button)
                    .buttonStyle(PillButtonStyle())
                    .fixedSize()
                    .help("Content level (needs your Wallhaven API key)")
                }

                RoundIconButton(
                    systemImage: model.showingFavorites ? "heart.fill" : "heart",
                    help: model.showingFavorites ? "Back to search results" : "Show favorites"
                ) { model.showingFavorites.toggle() }

                if !model.showingFavorites {
                    RoundIconButton(systemImage: "chevron.left", help: "Previous page") {
                        model.goToPage(model.query.page - 1)
                    }
                    .disabled(model.query.page <= 1)
                    Text("\(model.query.page)/\(model.lastPage)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                    RoundIconButton(systemImage: "chevron.right", help: "Next page") {
                        model.goToPage(model.query.page + 1)
                    }
                    .disabled(model.query.page >= model.lastPage)
                }
            }

            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                            ForEach(model.visible) { ThumbCell(wallpaper: $0, model: model).id($0.id) }
                        }
                        .padding(2)
                    }
                    // Scroll back to the last image you opened, on reopening and when coming back from a detail view.
                    .onAppear { scrollBack(proxy) }
                    .onChange(of: model.visible) { _, _ in scrollBack(proxy) }
                }
                if model.showingFavorites && model.favorites.isEmpty {
                    Text("No favorites yet. Hover a wallpaper and tap the heart.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                } else if !model.showingFavorites && model.wallpapers.isEmpty && !model.isLoading && model.errorMessage == nil {
                    Text("No wallpapers match. Try a lower minimum resolution or another content filter.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                if model.isLoading && model.wallpapers.isEmpty && !model.showingFavorites { ProgressView().controlSize(.small) }
                if let error = model.errorMessage, model.wallpapers.isEmpty, !model.showingFavorites {
                    HStack(spacing: 8) {
                        Text(error).font(.caption).lineLimit(2)
                        Button("Retry") { model.load() }.buttonStyle(PillButtonStyle())
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

extension WallhavenTabView {
    fileprivate func scrollBack(_ proxy: ScrollViewProxy) {
        guard !restoredScroll, let id = model.lastViewedID, model.visible.contains(where: { $0.id == id }) else { return }
        restoredScroll = true
        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
    }
}

struct DetailView: View {
    let wallpaper: Wallpaper
    @ObservedObject var model: WallhavenModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RemoteThumb(url: wallpaper.thumbs.original, model: model)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    RoundIconButton(systemImage: "chevron.left", help: "Back") { model.selected = nil }
                    Text(wallpaper.resolution).font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Spacer(minLength: 0)
                    RoundIconButton(systemImage: "arrow.up.left.and.arrow.down.right", help: "Large preview (Space)") {
                        model.togglePreview(wallpaper)
                    }
                }
                if let size = wallpaper.fileSize {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Button("Set as Wallpaper") { model.setDesktop(wallpaper) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                HStack(spacing: 6) {
                    Button {
                        model.toggleFavorite(wallpaper)
                    } label: {
                        Image(systemName: model.isFavorite(wallpaper) ? "heart.fill" : "heart")
                            .foregroundStyle(model.isFavorite(wallpaper) ? Color.pink : .white)
                    }
                    .buttonStyle(PillButtonStyle())
                    .help(model.isFavorite(wallpaper) ? "Remove from favorites" : "Add to favorites")
                    Button("Open") { model.openOnWeb(wallpaper) }.buttonStyle(PillButtonStyle())
                    Button("Copy Link") { model.copyLink(wallpaper) }.buttonStyle(PillButtonStyle())
                }
                Text(model.statusMessage ?? "Press Space for a large preview")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(model.statusMessage == nil ? 0.4 : 0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.space) { model.togglePreview(wallpaper); return .handled }
        .onAppear { focused = true }
    }
}
