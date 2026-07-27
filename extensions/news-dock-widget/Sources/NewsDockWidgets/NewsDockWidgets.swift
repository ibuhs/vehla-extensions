import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VehlaDockWidgetSDK

@MainActor
private final class NewsModel: ObservableObject {
    @Published private(set) var feeds: [NewsFeed] = []
    @Published private(set) var items: [NewsItem] = []
    @Published private(set) var readIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isDarkTheme = true
    @Published private(set) var tileTextColor = NSColor.white
    @Published var selectedFeedID: String? = nil
    @Published var showUnreadOnly = false
    @Published var expandedItemID: String? = nil

    private var repository: NewsRepository?
    private var fetcher = FeedFetcher()
    private var iconCache: FeedIconCache?
    private var activeDataDirectory: URL?
    private var loadTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var isActive = false
    private var context: VehlaDockWidgetContext?
    private var mutationGeneration = 0

    var unreadCount: Int {
        items.reduce(0) { partial, item in
            guard let feed = feed(for: item.feedID), !feed.isMuted else { return partial }
            return partial + (readIDs.contains(item.id) ? 0 : 1)
        }
    }

    var latestItem: NewsItem? {
        items.first { item in
            guard let feed = feed(for: item.feedID) else { return false }
            return feed.isEnabled && !feed.isMuted
        }
    }

    var orderedFeeds: [NewsFeed] {
        feeds.sorted { $0.sortOrder < $1.sortOrder }
    }

    var visibleFeeds: [NewsFeed] {
        orderedFeeds.filter(\.isEnabled)
    }

    func configure(context: VehlaDockWidgetContext) {
        self.context = context
        isDarkTheme = context.theme.isDark
        tileTextColor = context.theme.tileTextColor
        guard activeDataDirectory != context.dataDirectory else { return }
        activeDataDirectory = context.dataDirectory
        repository = NewsRepository(dataDirectory: context.dataDirectory)
        iconCache = FeedIconCache(dataDirectory: context.dataDirectory)
    }

    func updateTheme(_ theme: VehlaDockWidgetTheme) {
        isDarkTheme = theme.isDark
        tileTextColor = theme.tileTextColor
    }

    func start() {
        guard !isActive, let repository else { return }
        isActive = true
        isLoading = feeds.isEmpty && items.isEmpty
        errorMessage = nil
        let generation = mutationGeneration

        loadTask = Task { [weak self] in
            do {
                let state = try await repository.load()
                try Task.checkCancellation()
                guard let self else { return }
                guard generation == self.mutationGeneration else {
                    self.isLoading = false
                    self.startPolling()
                    return
                }
                self.feeds = state.feeds.sorted { $0.sortOrder < $1.sortOrder }
                self.items = state.items
                self.readIDs = Set(state.readIDs)
                self.lastRefreshAt = state.lastRefreshAt
                self.isLoading = false
                self.refresh(force: state.items.isEmpty)
                self.startPolling()
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.isLoading = false
                self.errorMessage = "Could not load saved news."
            }
        }
    }

    func stop() {
        isActive = false
        loadTask?.cancel()
        loadTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        pollTask?.cancel()
        pollTask = nil
        persist()
    }

    func refresh(force: Bool = true) {
        guard isActive, repository != nil else { return }
        if isRefreshing { return }

        let dueIDs: Set<String>
        if force {
            dueIDs = Set(feeds.filter { $0.isEnabled && !$0.isMuted }.map(\.id))
        } else {
            dueIDs = Set(feeds.filter { $0.isDue() }.map(\.id))
            if dueIDs.isEmpty { return }
        }
        guard !dueIDs.isEmpty else { return }

        isRefreshing = true
        statusMessage = nil
        let feedSnapshot = feeds
        let itemSnapshot = items
        let generation = mutationGeneration

        refreshTask?.cancel()
        refreshTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            let result = await self.fetcher.refresh(
                feeds: feedSnapshot,
                existingItems: itemSnapshot,
                onlyFeedIDs: dueIDs
            )
            guard !Task.isCancelled else {
                self.isRefreshing = false
                return
            }
            guard generation == self.mutationGeneration else {
                self.isRefreshing = false
                return
            }

            self.applyRefresh(result)
            self.isRefreshing = false
            self.persist()

            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled, generation == self.mutationGeneration {
                self.statusMessage = nil
            }
        }
    }

    func filteredItems(matching query: String) -> [NewsItem] {
        items.filter { item in
            guard let feed = feed(for: item.feedID), feed.isEnabled else { return false }
            if let selectedFeedID {
                if item.feedID != selectedFeedID { return false }
            } else if feed.isMuted {
                return false
            }
            if showUnreadOnly, readIDs.contains(item.id) {
                return false
            }
            return item.matches(query)
        }
    }

    func unreadCount(for feedID: String) -> Int {
        guard let feed = feed(for: feedID), !feed.isMuted else { return 0 }
        return items.reduce(0) { partial, item in
            guard item.feedID == feedID else { return partial }
            return partial + (readIDs.contains(item.id) ? 0 : 1)
        }
    }

    func feed(for id: String) -> NewsFeed? {
        feeds.first { $0.id == id }
    }

    func toggleExpanded(_ item: NewsItem) {
        if expandedItemID == item.id {
            expandedItemID = nil
        } else {
            expandedItemID = item.id
            markRead(item)
        }
    }

    func open(_ item: NewsItem) {
        guard let url = resolvedArticleURL(for: item) else {
            errorMessage = "This article has no openable link."
            return
        }
        markRead(item)
        if let context {
            context.open(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func copyLink(_ item: NewsItem) {
        guard let url = resolvedArticleURL(for: item) else {
            errorMessage = "This article has no link to copy."
            return
        }
        context?.copyText(url.absoluteString)
        statusMessage = "Link copied"
    }

    func markRead(_ item: NewsItem) {
        guard readIDs.insert(item.id).inserted else { return }
        persist()
    }

    func toggleRead(_ item: NewsItem) {
        if readIDs.contains(item.id) {
            readIDs.remove(item.id)
        } else {
            readIDs.insert(item.id)
        }
        persist()
    }

    func markAllVisibleRead(matching query: String) {
        let ids = filteredItems(matching: query).map(\.id)
        readIDs.formUnion(ids)
        persist()
    }

    func addFeed(title: String, urlString: String) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorMessage = "Enter a valid http(s) feed URL."
            return
        }
        if feeds.contains(where: {
            $0.urlString.caseInsensitiveCompare(trimmedURL) == .orderedSame
        }) {
            errorMessage = "That feed is already subscribed."
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let feed = NewsFeed(
            title: trimmedTitle.isEmpty ? url.host ?? "New Feed" : trimmedTitle,
            urlString: trimmedURL,
            refreshIntervalSeconds: NewsDefaults.inferredRefreshSeconds(for: trimmedURL),
            sortOrder: (feeds.map(\.sortOrder).max() ?? -1) + 1
        )
        bumpMutation()
        feeds.append(feed)
        persist()
        refresh(force: true)
    }

    func removeFeed(_ feed: NewsFeed) {
        bumpMutation()
        cancelRefresh()
        feeds.removeAll { $0.id == feed.id }
        items.removeAll { $0.feedID == feed.id }
        readIDs = Set(items.map(\.id).filter { readIDs.contains($0) })
        if selectedFeedID == feed.id { selectedFeedID = nil }
        if let expanded = expandedItemID,
           !items.contains(where: { $0.id == expanded }) {
            expandedItemID = nil
        }
        errorMessage = nil
        statusMessage = "Removed \(feed.title)"
        persist()
    }

    func toggleFeedEnabled(_ feed: NewsFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        bumpMutation()
        cancelRefresh()
        feeds[index].isEnabled.toggle()
        let enabled = feeds[index].isEnabled
        persist()
        if enabled { refresh(force: true) }
    }

    func toggleFeedMuted(_ feed: NewsFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        bumpMutation()
        feeds[index].isMuted.toggle()
        statusMessage = feeds[index].isMuted
            ? "Muted \(feed.title)"
            : "Unmuted \(feed.title)"
        persist()
    }

    func setRefreshInterval(_ interval: FeedRefreshInterval, for feed: NewsFeed) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        bumpMutation()
        feeds[index].refreshIntervalSeconds = interval.rawValue
        persist()
    }

    func restoreStarterFeeds() {
        bumpMutation()
        cancelRefresh()
        var existingURLs = Set(feeds.map { $0.urlString.lowercased() })
        var nextOrder = (feeds.map(\.sortOrder).max() ?? -1) + 1
        for starter in NewsDefaults.starterFeeds {
            guard existingURLs.insert(starter.urlString.lowercased()).inserted else {
                continue
            }
            var copy = starter
            copy.id = UUID().uuidString
            copy.sortOrder = nextOrder
            nextOrder += 1
            feeds.append(copy)
        }
        persist()
        refresh(force: true)
    }

    func exportOPML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.xml]
        panel.nameFieldStringValue = "vehla-news-feeds.opml"
        panel.title = "Export Feeds"
        panel.message = "Save an OPML backup of your subscriptions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let xml = OPMLDocument.export(feeds: feeds)
            try Data(xml.utf8).write(to: url, options: .atomic)
            statusMessage = "Exported \(feeds.count) feeds"
        } catch {
            errorMessage = "Could not export OPML."
        }
    }

    func importOPML() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.xml, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Feeds"
        panel.message = "Choose an OPML file to merge subscriptions."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try OPMLDocument.parse(data)
            bumpMutation()
            cancelRefresh()
            var existing = Set(feeds.map { $0.urlString.lowercased() })
            var nextOrder = (feeds.map(\.sortOrder).max() ?? -1) + 1
            var added = 0
            for var feed in imported {
                guard existing.insert(feed.urlString.lowercased()).inserted else { continue }
                feed.id = UUID().uuidString
                feed.sortOrder = nextOrder
                nextOrder += 1
                feeds.append(feed)
                added += 1
            }
            persist()
            statusMessage = added == 0
                ? "No new feeds in OPML"
                : "Imported \(added) feeds"
            if added > 0 { refresh(force: true) }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Could not import OPML."
        }
    }

    func loadIcon(for feed: NewsFeed) async -> NSImage? {
        guard let iconCache,
              let cgImage = await iconCache.image(for: feed),
              !Task.isCancelled else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: 48, height: 48))
    }

    private func bumpMutation() {
        mutationGeneration &+= 1
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
    }

    private func applyRefresh(
        _ result: (items: [NewsItem], feedUpdates: [NewsFeed], errors: [String])
    ) {
        let currentIDs = Set(feeds.map(\.id))
        let updatesByID = Dictionary(
            uniqueKeysWithValues: result.feedUpdates
                .filter { currentIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        feeds = feeds.map { feed in
            guard let updated = updatesByID[feed.id] else { return feed }
            var merged = feed
            if !updated.title.isEmpty { merged.title = updated.title }
            if let site = updated.siteURLString, !site.isEmpty {
                merged.siteURLString = site
            }
            if let art = updated.artworkURLString, !art.isEmpty {
                merged.artworkURLString = art
            }
            merged.lastFetchedAt = updated.lastFetchedAt ?? merged.lastFetchedAt
            if updated.refreshIntervalSeconds != NewsDefaults.defaultRefreshSeconds {
                merged.refreshIntervalSeconds = updated.refreshIntervalSeconds
            }
            return merged
        }

        items = result.items.filter { currentIDs.contains($0.feedID) }
        lastRefreshAt = Date()

        if !result.errors.isEmpty {
            let activeTitles = Set(feeds.map(\.title))
            let relevant = result.errors.filter { error in
                activeTitles.contains { title in error.hasPrefix(title + ":") }
            }
            errorMessage = relevant.prefix(2).joined(separator: "\n").nilIfEmpty
        } else {
            errorMessage = nil
        }
        statusMessage = "Updated \(items.count) articles"
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: NewsDefaults.pollTick)
                guard !Task.isCancelled else { return }
                self?.refresh(force: false)
            }
        }
    }

    private func persist() {
        guard let repository else { return }
        let generation = mutationGeneration
        let state = NewsSavedState(
            feeds: feeds,
            items: items,
            readIDs: Array(readIDs),
            lastRefreshAt: lastRefreshAt
        )
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            do {
                try Task.checkCancellation()
                guard let self, generation == self.mutationGeneration else { return }
                try await repository.save(state)
            } catch is CancellationError {
                return
            } catch {
                guard let self, generation == self.mutationGeneration else { return }
                self.errorMessage = "Could not save news state."
            }
        }
    }

    private func resolvedArticleURL(for item: NewsItem) -> URL? {
        let trimmed = item.linkString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        if trimmed.hasPrefix("//"),
           let url = URL(string: "https:\(trimmed)"),
           url.scheme == "https" {
            return url
        }
        if trimmed.hasPrefix("/"),
           let feed = feed(for: item.feedID),
           let base = feed.siteURL ?? feed.feedURL,
           let url = URL(string: trimmed, relativeTo: base)?.absoluteURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }
}

@objc(NewsDockWidgetPlugin)
public final class NewsDockWidgetPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [
        VehlaDockWidgetDescriptor(
            id: "news-reader",
            title: "News",
            subtitle: "RSS and Atom reader with background refresh",
            systemImage: "newspaper.fill",
            preferredPopupWidth: 500,
            preferredPopupHeight: 640,
            supportedSurfaces: [.compact, .inline, .popup]
        ),
    ]

    @MainActor private let model = NewsModel()

    @MainActor
    public func makeViewController(
        widgetID: String,
        surface: VehlaDockWidgetSurface,
        context: VehlaDockWidgetContext
    ) throws -> NSViewController {
        guard widgetID == "news-reader" else {
            throw CocoaError(.fileNoSuchFile)
        }
        model.configure(context: context)
        return NSHostingController(
            rootView: NewsRootView(surface: surface, model: model)
        )
    }

    @MainActor
    public func widget(
        _ widgetID: String,
        didEnter phase: VehlaDockWidgetVisibilityPhase
    ) {
        phase == .hidden ? model.stop() : model.start()
    }

    @MainActor
    public func widget(
        _ widgetID: String,
        themeDidChange theme: VehlaDockWidgetTheme
    ) {
        model.updateTheme(theme)
    }

    @MainActor
    public func widgetWillClose(_ widgetID: String) {
        model.stop()
    }
}

private struct PopupChromeKey: EnvironmentKey {
    static let defaultValue: Color = .white
}

private struct PopupChromeIsDarkKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var popupChrome: Color {
        get { self[PopupChromeKey.self] }
        set { self[PopupChromeKey.self] = newValue }
    }

    /// Matches `theme.isDark`: true keeps original white chrome.
    var popupChromeIsDark: Bool {
        get { self[PopupChromeIsDarkKey.self] }
        set { self[PopupChromeIsDarkKey.self] = newValue }
    }
}

private struct NewsRootView: View {
    let surface: VehlaDockWidgetSurface
    @ObservedObject var model: NewsModel

    @ViewBuilder
    var body: some View {
        switch surface {
        case .compact:
            CompactNewsView(model: model)
        case .inline:
            InlineNewsView(model: model)
        case .popup:
            PopupNewsView(model: model)
                // Messages recipe, Light theme only: white palette × black.
                // Other themes keep identity multiply so accents/icons stay original.
                .environment(\.popupChrome, .white)
                .environment(\.popupChromeIsDark, model.isDarkTheme)
                .colorMultiply(model.isDarkTheme ? .white : .black)
        @unknown default:
            EmptyView()
        }
    }
}

// MARK: - Palette

private enum NewsPalette {
    static let accent = Color(red: 0.35, green: 0.72, blue: 1.0)
    static let success = Color(red: 0.42, green: 0.88, blue: 0.62)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.32)
    static let link = Color(red: 0.55, green: 0.78, blue: 1.0)
    static let allFeeds = Color(red: 0.72, green: 0.55, blue: 1.0)

    private static let spectrum: [Color] = [
        Color(red: 1.00, green: 0.42, blue: 0.42),
        Color(red: 1.00, green: 0.62, blue: 0.28),
        Color(red: 1.00, green: 0.82, blue: 0.28),
        Color(red: 0.42, green: 0.88, blue: 0.55),
        Color(red: 0.30, green: 0.82, blue: 0.86),
        Color(red: 0.35, green: 0.72, blue: 1.00),
        Color(red: 0.55, green: 0.55, blue: 1.00),
        Color(red: 0.88, green: 0.48, blue: 0.95),
        Color(red: 1.00, green: 0.48, blue: 0.72),
    ]

    static func color(forFeedID feedID: String?, title: String = "") -> Color {
        if let branded = brandedColor(for: title) { return branded }
        let key = feedID?.nilIfEmpty ?? title
        guard !key.isEmpty else { return accent }
        let hash = key.utf8.reduce(0) { ($0 &+ Int($1) &* 31) }
        return spectrum[abs(hash) % spectrum.count]
    }

    private static func brandedColor(for title: String) -> Color? {
        let lowered = title.lowercased()
        if lowered.contains("apple") { return Color(red: 0.40, green: 0.78, blue: 1.00) }
        if lowered.contains("bbc") { return Color(red: 1.00, green: 0.32, blue: 0.38) }
        if lowered.contains("npr") { return Color(red: 0.62, green: 0.42, blue: 0.95) }
        if lowered.contains("verge") { return Color(red: 0.95, green: 0.38, blue: 0.55) }
        if lowered.contains("hacker") { return Color(red: 1.00, green: 0.55, blue: 0.20) }
        if lowered.contains("crime") { return Color(red: 0.45, green: 0.78, blue: 0.95) }
        return nil
    }
}

// MARK: - Surfaces

private extension NSColor {
    var contrastingColor: Color {
        guard let rgb = usingColorSpace(.sRGB) else { return .black }
        let luminance = 0.2126 * rgb.redComponent
            + 0.7152 * rgb.greenComponent
            + 0.0722 * rgb.blueComponent
        return luminance > 0.52 ? .black : .white
    }
}

private struct CompactNewsView: View {
    @ObservedObject var model: NewsModel

    private var tileColor: Color {
        Color(nsColor: model.tileTextColor)
    }

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "newspaper.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(tileColor)
                if model.unreadCount > 0 {
                    Text(badgeText)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(model.tileTextColor.contrastingColor)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tileColor))
                        .offset(x: 6, y: -4)
                }
            }
            Text(model.isRefreshing ? "…" : "News")
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tileColor)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(
            model.unreadCount > 0
                ? "\(model.unreadCount) unread articles"
                : "News reader"
        )
    }

    private var badgeText: String {
        model.unreadCount > 99 ? "99+" : "\(model.unreadCount)"
    }
}

private struct InlineNewsView: View {
    @ObservedObject var model: NewsModel

    private var tileColor: Color {
        Color(nsColor: model.tileTextColor)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "newspaper.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tileColor)

            if model.isLoading {
                Text("Loading feeds…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tileColor.opacity(0.72))
            } else if let latest = model.latestItem {
                Button {
                    model.open(latest)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(latest.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(tileColor)
                        Text(latest.feedTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(tileColor.opacity(0.62))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Open \(latest.title)")
            } else {
                Text(model.isRefreshing ? "Refreshing…" : "No headlines yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tileColor.opacity(0.72))
            }

            Spacer(minLength: 0)

            if model.unreadCount > 0 {
                Text("\(model.unreadCount)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(tileColor.opacity(0.86))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct PopupNewsView: View {
    @ObservedObject var model: NewsModel
    @State private var searchText = ""
    @State private var showingAddFeed = false
    @State private var showingManageFeeds = false
    @State private var newFeedTitle = ""
    @State private var newFeedURL = ""

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleItems: [NewsItem] {
        model.filteredItems(matching: normalizedSearch)
    }

    @Environment(\.popupChrome) private var chrome

    var body: some View {
        VStack(spacing: 12) {
            if showingManageFeeds {
                ManageFeedsPanel(model: model) {
                    showingManageFeeds = false
                }
            } else if showingAddFeed {
                AddFeedPanel(
                    title: $newFeedTitle,
                    urlString: $newFeedURL,
                    onCancel: {
                        showingAddFeed = false
                        newFeedTitle = ""
                        newFeedURL = ""
                    },
                    onAdd: {
                        model.addFeed(title: newFeedTitle, urlString: newFeedURL)
                        showingAddFeed = false
                        newFeedTitle = ""
                        newFeedURL = ""
                    }
                )
            } else {
                header
                divider
                feedChips
                toolbar
                divider
                content
            }
        }
        .padding(16)
        .foregroundStyle(chrome)
        .tint(NewsPalette.accent)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(NewsPalette.accent.opacity(0.9))
            TextField(
                "",
                text: $searchText,
                prompt: Text("Search headlines")
                    .foregroundStyle(chrome.opacity(0.55))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(chrome)
            .tint(NewsPalette.accent)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NewsPalette.accent.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 2)
    }

    private var feedChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FeedChip(
                    title: "All",
                    count: model.unreadCount,
                    accent: NewsPalette.allFeeds,
                    selected: model.selectedFeedID == nil,
                    icon: nil,
                    muted: false
                ) {
                    model.selectedFeedID = nil
                }
                ForEach(model.visibleFeeds) { feed in
                    FeedChip(
                        title: feed.title,
                        count: model.unreadCount(for: feed.id),
                        accent: NewsPalette.color(forFeedID: feed.id, title: feed.title),
                        selected: model.selectedFeedID == feed.id,
                        feed: feed,
                        model: model,
                        muted: feed.isMuted
                    ) {
                        model.selectedFeedID = feed.id
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TintIconButton(
                symbol: "arrow.clockwise",
                help: "Refresh due feeds",
                tint: NewsPalette.accent
            ) {
                model.refresh(force: true)
            }
            .disabled(model.isRefreshing)

            TintIconButton(
                symbol: model.showUnreadOnly
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle",
                help: model.showUnreadOnly ? "Show all articles" : "Unread only",
                tint: model.showUnreadOnly ? NewsPalette.warning : NewsPalette.accent
            ) {
                model.showUnreadOnly.toggle()
            }

            TintIconButton(
                symbol: "checkmark.circle",
                help: "Mark visible as read",
                tint: NewsPalette.success
            ) {
                model.markAllVisibleRead(matching: normalizedSearch)
            }

            Spacer(minLength: 0)

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(NewsPalette.accent)
            } else if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(NewsPalette.success.opacity(0.9))
                    .lineLimit(1)
            } else if let lastRefreshAt = model.lastRefreshAt {
                Text(lastRefreshAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(NewsPalette.accent.opacity(0.8))
                    .help("Last refreshed")
            }

            TintIconButton(
                symbol: "plus",
                help: "Add feed",
                tint: NewsPalette.success
            ) {
                showingAddFeed = true
            }
            TintIconButton(
                symbol: "slider.horizontal.3",
                help: "Manage feeds",
                tint: NewsPalette.allFeeds
            ) {
                showingManageFeeds = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            Spacer()
            VStack(spacing: 10) {
                ProgressView().tint(NewsPalette.accent)
                Text("Loading news…")
                    .foregroundStyle(chrome.opacity(0.75))
            }
            Spacer()
        } else if model.feeds.isEmpty {
            Spacer()
            StatusView(
                symbol: "newspaper",
                message: "Add an RSS or Atom feed to get started",
                tint: NewsPalette.accent
            )
            Button("Restore starter feeds") {
                model.restoreStarterFeeds()
            }
            .buttonStyle(.plain)
            .foregroundStyle(NewsPalette.accent)
            Spacer()
        } else if visibleItems.isEmpty {
            Spacer()
            StatusView(
                symbol: normalizedSearch.isEmpty
                    ? (model.showUnreadOnly ? "checkmark.circle" : "tray")
                    : "magnifyingglass",
                message: emptyMessage,
                tint: model.showUnreadOnly ? NewsPalette.success : NewsPalette.accent
            )
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.45))
                    .padding(.top, 4)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    SectionTitle(
                        title: sectionTitle,
                        count: visibleItems.count,
                        accent: sectionAccent
                    )
                    ForEach(visibleItems) { item in
                        ArticleRow(item: item, model: model)
                    }
                }
                .padding(.trailing, 4)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sectionAccent: Color {
        if let selectedFeedID = model.selectedFeedID,
           let feed = model.feeds.first(where: { $0.id == selectedFeedID }) {
            return NewsPalette.color(forFeedID: feed.id, title: feed.title)
        }
        if model.showUnreadOnly { return NewsPalette.warning }
        return NewsPalette.accent
    }

    private var sectionTitle: String {
        if model.showUnreadOnly { return "Unread" }
        if model.selectedFeedID != nil {
            return model.feeds.first { $0.id == model.selectedFeedID }?.title ?? "Feed"
        }
        return normalizedSearch.isEmpty ? "Latest" : "Results"
    }

    private var emptyMessage: String {
        if !normalizedSearch.isEmpty { return "No matching headlines" }
        if model.showUnreadOnly { return "You're all caught up" }
        return model.isRefreshing ? "Fetching headlines…" : "No articles yet"
    }

    private var divider: some View {
        LinearGradient(
            colors: [
                NewsPalette.accent.opacity(0.05),
                NewsPalette.accent.opacity(0.45),
                NewsPalette.allFeeds.opacity(0.45),
                NewsPalette.allFeeds.opacity(0.05),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

// MARK: - Rows & panels

private struct ArticleRow: View {
    let item: NewsItem
    @ObservedObject var model: NewsModel

    private var isRead: Bool { model.readIDs.contains(item.id) }
    private var isExpanded: Bool { model.expandedItemID == item.id }
    private var feedColor: Color {
        NewsPalette.color(forFeedID: item.feedID, title: item.feedTitle)
    }
    private var feed: NewsFeed? { model.feed(for: item.feedID) }

    @Environment(\.popupChrome) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    model.toggleExpanded(item)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if let feed {
                            FeedIconView(feed: feed, model: model, size: 18)
                                .padding(.top, 1)
                        } else {
                            Circle()
                                .fill(isRead ? feedColor.opacity(0.28) : feedColor)
                                .frame(width: 7, height: 7)
                                .padding(.top, 5)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 12, weight: isRead ? .medium : .semibold))
                                .foregroundStyle(chrome.opacity(isRead ? 0.72 : 1))
                                .multilineTextAlignment(.leading)
                                .lineLimit(isExpanded ? 4 : 2)
                            HStack(spacing: 6) {
                                Text(item.feedTitle)
                                    .foregroundStyle(feedColor.opacity(isRead ? 0.75 : 1))
                                    .lineLimit(1)
                                if let publishedAt = item.publishedAt {
                                    Text("·").foregroundStyle(chrome.opacity(0.45))
                                    Text(publishedAt, style: .relative)
                                        .foregroundStyle(chrome.opacity(0.55))
                                        .lineLimit(1)
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            if !isExpanded, !item.summary.isEmpty {
                                Text(item.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(chrome.opacity(0.62))
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(chrome.opacity(0.45))
                            .padding(.top, 3)
                    }
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Show details")
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 11))
                            .foregroundStyle(chrome.opacity(0.78))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No summary for this article.")
                            .font(.system(size: 11))
                            .foregroundStyle(chrome.opacity(0.55))
                    }
                    if let author = item.author, !author.isEmpty {
                        Text(author)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(feedColor.opacity(0.9))
                    }

                    HStack(spacing: 10) {
                        DetailActionButton(
                            title: "Open",
                            symbol: "safari",
                            tint: NewsPalette.accent
                        ) {
                            model.open(item)
                        }
                        DetailActionButton(
                            title: "Copy",
                            symbol: "link",
                            tint: NewsPalette.link
                        ) {
                            model.copyLink(item)
                        }
                        DetailActionButton(
                            title: isRead ? "Unread" : "Mark read",
                            symbol: isRead ? "circle" : "checkmark.circle",
                            tint: NewsPalette.success
                        ) {
                            model.toggleRead(item)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(feedColor.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(feedColor.opacity(0.35), lineWidth: 1)
                )
            }
        }
        .padding(.vertical, 3)
    }
}

private struct DetailActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

private struct FeedChip: View {
    let title: String
    let count: Int
    let accent: Color
    let selected: Bool
    var feed: NewsFeed? = nil
    var model: NewsModel? = nil
    var icon: NSImage? = nil
    var muted: Bool = false
    let action: () -> Void

    @Environment(\.popupChrome) private var chrome
    @Environment(\.popupChromeIsDark) private var isDarkChrome

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let feed, let model {
                    FeedIconView(feed: feed, model: model, size: 12)
                } else {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .lineLimit(1)
                    .opacity(muted ? 0.65 : 1)
                if muted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(
                            selected && isDarkChrome
                                ? .black.opacity(0.7)
                                : (isDarkChrome ? accent : chrome.opacity(0.72))
                        )
                }
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(
                            selected && isDarkChrome
                                ? .black
                                : (isDarkChrome ? accent : chrome.opacity(0.86))
                        )
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(
                                selected && isDarkChrome
                                    ? .white.opacity(0.92)
                                    : (isDarkChrome
                                        ? accent.opacity(0.22)
                                        : chrome.opacity(0.14))
                            )
                        )
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected && isDarkChrome ? .black : chrome)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? accent : accent.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(
                    accent.opacity(selected ? 0 : 0.45),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .opacity(muted && !selected ? 0.75 : 1)
    }
}

/// Renders bitmap art in an AppKit image view so SwiftUI `colorMultiply` on the
/// popup (used for light-theme contrast) does not desaturate feed icons.
private struct AppKitImageView: NSViewRepresentable {
    let image: NSImage
    let size: CGFloat
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        configure(view)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        configure(view)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSImageView,
        context: Context
    ) -> CGSize? {
        CGSize(width: size, height: size)
    }

    private func configure(_ view: NSImageView) {
        view.image = image
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = cornerRadius > 0
    }
}

private struct FeedIconView: View {
    let feed: NewsFeed
    @ObservedObject var model: NewsModel
    let size: CGFloat
    @State private var icon: NSImage?
    @Environment(\.popupChrome) private var chrome

    var body: some View {
        Group {
            if let icon {
                // Host via AppKit so popup colorMultiply (light theme) doesn't flatten brand art.
                AppKitImageView(
                    image: icon,
                    size: size,
                    cornerRadius: size * 0.22
                )
            } else {
                RoundedRectangle(cornerRadius: size * 0.22)
                    .fill(NewsPalette.color(forFeedID: feed.id, title: feed.title).opacity(0.85))
                    .overlay(
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: size * 0.45, weight: .bold))
                            .foregroundStyle(chrome)
                    )
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(feed.id)|\(feed.artworkURLString ?? "")") {
            icon = await model.loadIcon(for: feed)
        }
    }
}

private struct AddFeedPanel: View {
    @Binding var title: String
    @Binding var urlString: String
    let onCancel: () -> Void
    let onAdd: () -> Void

    @Environment(\.popupChrome) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add Feed")
                    .font(.headline.bold())
                    .foregroundStyle(NewsPalette.accent)
                Spacer()
                TintIconButton(
                    symbol: "xmark",
                    help: "Cancel",
                    tint: chrome.opacity(0.75),
                    action: onCancel
                )
            }

            labeledField("Title (optional)", text: $title, prompt: "Feed name")
            labeledField("Feed URL", text: $urlString, prompt: "https://example.com/feed.xml")

            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(chrome.opacity(0.75))
                Spacer()
                Button("Add Feed", action: onAdd)
                    .foregroundStyle(NewsPalette.success)
                    .disabled(urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private func labeledField(
        _ label: String,
        text: Binding<String>,
        prompt: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(NewsPalette.accent.opacity(0.85))
            TextField(
                "",
                text: text,
                prompt: Text(prompt).foregroundStyle(chrome.opacity(0.55))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(chrome)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NewsPalette.accent.opacity(0.35), lineWidth: 1)
            )
        }
    }
}

private struct ManageFeedsPanel: View {
    @ObservedObject var model: NewsModel
    let onClose: () -> Void

    @Environment(\.popupChrome) private var chrome

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Manage Feeds")
                    .font(.headline.bold())
                    .foregroundStyle(NewsPalette.allFeeds)
                Spacer()
                TintIconButton(
                    symbol: "square.and.arrow.down",
                    help: "Import OPML",
                    tint: NewsPalette.accent
                ) {
                    model.importOPML()
                }
                TintIconButton(
                    symbol: "square.and.arrow.up",
                    help: "Export OPML",
                    tint: NewsPalette.link
                ) {
                    model.exportOPML()
                }
                TintIconButton(
                    symbol: "xmark",
                    help: "Close",
                    tint: chrome.opacity(0.75),
                    action: onClose
                )
            }

            if model.orderedFeeds.isEmpty {
                Spacer()
                StatusView(
                    symbol: "tray",
                    message: "No feeds subscribed",
                    tint: NewsPalette.accent
                )
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.orderedFeeds) { feed in
                            ManageFeedRow(feed: feed, model: model)
                        }
                    }
                }
            }

            Button("Restore starter feeds") {
                model.restoreStarterFeeds()
            }
            .buttonStyle(.plain)
            .foregroundStyle(NewsPalette.accent)
        }
    }
}

private struct ManageFeedRow: View {
    let feed: NewsFeed
    @ObservedObject var model: NewsModel

    private var accent: Color {
        NewsPalette.color(forFeedID: feed.id, title: feed.title)
    }

    @Environment(\.popupChrome) private var chrome
    @Environment(\.popupChromeIsDark) private var isDarkChrome

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FeedIconView(feed: feed, model: model, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(feed.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(chrome)
                        if feed.isMuted {
                            Text("MUTED")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(NewsPalette.warning)
                        }
                    }
                    Text(feed.urlString)
                        .font(.system(size: 10))
                        .foregroundStyle(chrome.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                TintIconButton(
                    symbol: feed.isMuted ? "bell.slash.fill" : "bell.fill",
                    help: feed.isMuted ? "Unmute feed" : "Mute feed",
                    tint: feed.isMuted ? NewsPalette.warning : NewsPalette.accent
                ) {
                    model.toggleFeedMuted(feed)
                }
                TintIconButton(
                    symbol: feed.isEnabled ? "pause.circle" : "play.circle",
                    help: feed.isEnabled ? "Disable feed" : "Enable feed",
                    tint: feed.isEnabled ? NewsPalette.warning : NewsPalette.success
                ) {
                    model.toggleFeedEnabled(feed)
                }
                TintIconButton(
                    symbol: "trash",
                    help: "Remove feed",
                    tint: Color(red: 1.0, green: 0.45, blue: 0.42)
                ) {
                    model.removeFeed(feed)
                }
            }

            HStack(spacing: 6) {
                Text("REFRESH")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(chrome.opacity(0.45))
                ForEach(FeedRefreshInterval.allCases) { interval in
                    let selected = feed.refreshInterval == interval
                    Button {
                        model.setRefreshInterval(interval, for: feed)
                    } label: {
                        Text(interval.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(
                                selected && isDarkChrome
                                    ? .black
                                    : chrome.opacity(selected ? 1 : 0.8)
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(
                                    selected
                                        ? (isDarkChrome ? accent : accent.opacity(0.42))
                                        : accent.opacity(0.15)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(feed.isEnabled ? 1 : 0.55)
    }
}

private struct TintIconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white.opacity(0.86)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 18, height: 18)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private struct SectionTitle: View {
    let title: String
    let count: Int
    var accent: Color = NewsPalette.accent
    @Environment(\.popupChromeIsDark) private var isDarkChrome
    @Environment(\.popupChrome) private var chrome

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(
                    isDarkChrome ? accent.opacity(0.95) : chrome.opacity(0.62)
                )
            Text("\(count)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(
                    isDarkChrome ? accent.opacity(0.75) : chrome.opacity(0.55)
                )
        }
    }
}

private struct StatusView: View {
    let symbol: String
    let message: String
    var tint: Color = NewsPalette.accent

    @Environment(\.popupChrome) private var chrome

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(chrome.opacity(0.72))
        }
    }
}
