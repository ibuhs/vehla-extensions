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
    @Published var selected: Wallpaper?
    @Published var statusMessage: String?
    @Published var favorites: [Wallpaper] = []
    @Published var showingFavorites = false

    /// What the grid shows: saved favorites, or the current search results.
    var visible: [Wallpaper] { showingFavorites ? favorites : wallpapers }

    private var notch: VehlaNotch?
    private let client = WallhavenClient()
    private var loadTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var hasLoaded = false

    func attach(_ notch: VehlaNotch) {
        self.notch = notch
        let key = notch.secret(named: "apiKey")
        Task { await client.setAPIKey(key) }
        loadPersisted()
    }

    // MARK: Persistence (favorites and preferences live in the extension's data folder)

    private struct Prefs: Codable { var minResolution: MinResolution }

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
        write(Prefs(minResolution: value), to: prefsURL)
        showingFavorites = false
        query.page = 1
        query.seed = nil
        load()
    }

    func detach() {
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
    }

    func goToPage(_ page: Int) {
        guard page >= 1, page <= lastPage, page != query.page else { return }
        query.page = page
        load()
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
                self.wallpapers = page.data
                self.lastPage = max(page.meta.lastPage, 1)
                self.query.seed = page.meta.seed
                self.hasLoaded = true
                self.isLoading = false
                self.errorMessage = nil
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
        model.startIfNeeded()
        return NSHostingController(rootView: WallhavenTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) {
        if isVisible { model.startIfNeeded() }
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
    @State private var text = ""
    @State private var sorting: WallhavenSorting = .toplist

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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                        ForEach(model.visible) { ThumbCell(wallpaper: $0, model: model) }
                    }
                    .padding(2)
                }
                if model.showingFavorites && model.favorites.isEmpty {
                    Text("No favorites yet. Hover a wallpaper and tap the heart.")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                } else if !model.showingFavorites && model.wallpapers.isEmpty && !model.isLoading && model.errorMessage == nil {
                    Text("No wallpapers match. Try a lower minimum resolution.")
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

struct DetailView: View {
    let wallpaper: Wallpaper
    @ObservedObject var model: WallhavenModel

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
                Text(model.statusMessage ?? " ")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
