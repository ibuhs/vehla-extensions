import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VehlaNativeUISDK

@MainActor
final class CoverArtSearchStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [CoverArtResult] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    let context: VehlaWorkspaceContext
    private var searchTask: Task<Void, Never>?

    init(context: VehlaWorkspaceContext) {
        self.context = context
        query = context.launchRequest.query
        if !query.isEmpty {
            search()
        }
    }

    deinit {
        searchTask?.cancel()
    }

    func search() {
        searchTask?.cancel()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            return
        }

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                results = try await CoverArtSearchService.shared.search(query)
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                results = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func copyImage(for result: CoverArtResult) {
        Task {
            do {
                let data = try await CoverArtSearchService.shared.imageData(for: result)
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setData(data, forType: .png)
                    context.showMessage("Copied \(result.title) cover art.")
                }
            } catch {
                errorMessage = "Could not download that cover image."
            }
        }
    }

    func copyURL(for result: CoverArtResult) {
        context.copyText(result.imageURL.absoluteString)
        context.showMessage("Copied image URL.")
    }

    func openIMDb(for result: CoverArtResult) {
        context.open(result.imdbURL)
    }

    func dragProvider(for result: CoverArtResult) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = result.imageFileName
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            let progress = Progress(totalUnitCount: 1)
            let task = Task {
                do {
                    let data = try await CoverArtSearchService.shared.imageData(for: result)
                    guard !Task.isCancelled else {
                        completion(nil, CancellationError())
                        return
                    }
                    progress.completedUnitCount = 1
                    completion(data, nil)
                } catch {
                    completion(nil, error)
                }
            }
            progress.cancellationHandler = {
                task.cancel()
            }
            return progress
        }
        return provider
    }
}

struct CoverArtSearchView: View {
    @ObservedObject var store: CoverArtSearchStore
    @ObservedObject var theme: ThemeCoordinator

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.18)

            if store.isSearching {
                ProgressView("Searching IMDb…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = store.errorMessage {
                emptyState(title: "No cover art", message: error, symbol: "photo.badge.exclamationmark")
            } else if store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState(
                    title: "Search for cover art",
                    message: "Find posters for movies, shows, anime, and games.",
                    symbol: "photo.on.rectangle.angled"
                )
            } else {
                resultGrid
            }
        }
        .frame(minWidth: 600, minHeight: 480)
        .background(Color(nsColor: theme.theme.backgroundColor).opacity(0.92))
        .foregroundStyle(Color(nsColor: theme.theme.primaryTextColor))
        .preferredColorScheme(theme.theme.isDark ? .dark : .light)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
            TextField("Search a movie, show, anime, or game", text: $store.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .onSubmit { store.search() }
                .onChange(of: store.query) { _, _ in store.search() }
            if store.isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !store.query.isEmpty {
                Button {
                    store.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var resultGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: 4
                ),
                alignment: .leading,
                spacing: 18
            ) {
                ForEach(store.results) { result in
                    CoverArtCard(result: result, store: store)
                }
            }
            .padding(18)
        }
        .scrollContentBackground(.hidden)
    }

    private func emptyState(title: String, message: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 32))
                .foregroundStyle(Color(nsColor: theme.theme.accentColor))
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(Color(nsColor: theme.theme.secondaryTextColor))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

private struct CoverArtCard: View {
    let result: CoverArtResult
    @ObservedObject var store: CoverArtSearchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { proxy in
                AsyncImage(url: result.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.primary.opacity(0.12))
            }

            Text(result.title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Text([result.kind, result.year.map(String.init), result.dimensions]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onDrag {
            store.dragProvider(for: result)
        }
        .help("Drag the cover art to Shelf, Finder, or another app")
        .contextMenu {
            Button("Copy Image to Clipboard") { store.copyImage(for: result) }
            Button("Copy Image URL") { store.copyURL(for: result) }
            Button("Open IMDb Page") { store.openIMDb(for: result) }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
