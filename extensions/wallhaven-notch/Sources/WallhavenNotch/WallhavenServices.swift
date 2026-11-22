import AppKit
import Foundation

struct Wallpaper: Codable, Identifiable, Hashable, Sendable {
    struct Thumbs: Codable, Hashable, Sendable {
        let large: URL
        let original: URL
        let small: URL
    }

    let id: String
    let url: URL
    let path: URL
    let resolution: String
    let fileSize: Int?
    let colors: [String]
    let thumbs: Thumbs
    let views: Int?
    let favorites: Int?

    enum CodingKeys: String, CodingKey {
        case id, url, path, resolution, colors, thumbs, views, favorites
        case fileSize = "file_size"
    }
}

struct WallhavenPage: Codable, Sendable {
    struct Meta: Codable, Sendable {
        let currentPage: Int
        let lastPage: Int
        let seed: String?

        enum CodingKeys: String, CodingKey {
            case currentPage = "current_page"
            case lastPage = "last_page"
            case seed
        }
    }

    let data: [Wallpaper]
    let meta: Meta
}

enum WallhavenSorting: String, CaseIterable, Identifiable, Sendable {
    case toplist, latest, hot, random, relevance, views, favorites

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum MinResolution: String, CaseIterable, Identifiable, Codable, Sendable {
    case any, hd, qhd, uhd, fiveK

    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: return "Any size"
        case .hd: return "1080p+"
        case .qhd: return "1440p+"
        case .uhd: return "4K+"
        case .fiveK: return "5K+"
        }
    }
    /// Wallhaven's `atleast` value.
    var atLeast: String? {
        switch self {
        case .any: return nil
        case .hd: return "1920x1080"
        case .qhd: return "2560x1440"
        case .uhd: return "3840x2160"
        case .fiveK: return "5120x2880"
        }
    }
}

/// How much Wallhaven shows. Tiers add up: Regular is just that; Sketchy is Regular plus sketchy; NSFW is everything.
/// Sketchy and NSFW need an API key.
enum PurityTier: Int, CaseIterable, Identifiable, Sendable {
    case regular, sketchy, nsfw

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .regular: return "Regular"
        case .sketchy: return "Sketchy"
        case .nsfw: return "NSFW"
        }
    }

    /// The API's three-digit `purity` flag (SFW, Sketchy, NSFW).
    var parameter: String {
        switch self {
        case .regular: return "100"
        case .sketchy: return "110"
        case .nsfw: return "111"
        }
    }

    /// Reads a setting saved by the earlier multi-select version (a bit mask: 1 SFW, 2 sketchy, 4 NSFW).
    init(legacyMask mask: Int) {
        if mask & 4 != 0 { self = .nsfw } else if mask & 2 != 0 { self = .sketchy } else { self = .regular }
    }
}

struct WallhavenQuery: Equatable, Sendable {
    var tier: PurityTier = .regular
    var minResolution: MinResolution = .any
    var text = ""
    var sorting: WallhavenSorting = .toplist
    var page = 1
    var seed: String?
}

enum WallhavenError: LocalizedError {
    case badResponse(Int)
    case rateLimited
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Wallhaven returned HTTP \(code)."
        case .rateLimited: return "Wallhaven rate limit reached. Try again in a minute."
        case .notAnImage: return "The download was not a valid image."
        }
    }
}

actor WallhavenClient {
    private let session: URLSession
    private var apiKey: String?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 120
        // Images are cached (with a limit) after decoding; keeping the downloads as well would double the cost.
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = ["User-Agent": "VehlaWallhavenDockWidget/1.0"]
        session = URLSession(configuration: configuration)
    }

    func setAPIKey(_ key: String?) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // The key is only ever attached to Wallhaven API requests.
        if let apiKey, url.host == "wallhaven.cc" {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        return request
    }

    /// The search URL. Without an API key the tier is always Regular, whatever was asked for.
    static func searchURL(for query: WallhavenQuery, hasAPIKey: Bool) -> URL {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        let tier = hasAPIKey ? query.tier : .regular
        var items = [
            URLQueryItem(name: "categories", value: "111"),
            URLQueryItem(name: "purity", value: tier.parameter),
            URLQueryItem(name: "sorting", value: query.sorting.rawValue),
            URLQueryItem(name: "page", value: String(query.page)),
        ]
        if let atLeast = query.minResolution.atLeast {
            items.append(URLQueryItem(name: "atleast", value: atLeast))
        }
        if !query.text.isEmpty { items.append(URLQueryItem(name: "q", value: query.text)) }
        if query.sorting == .toplist { items.append(URLQueryItem(name: "topRange", value: "1M")) }
        if query.sorting == .random, let seed = query.seed {
            items.append(URLQueryItem(name: "seed", value: seed))
        }
        components.queryItems = items
        return components.url!
    }

    func search(_ query: WallhavenQuery) async throws -> WallhavenPage {
        let url = Self.searchURL(for: query, hasAPIKey: apiKey != nil)
        let (data, response) = try await session.data(for: request(url))
        try Self.check(response)
        return try JSONDecoder().decode(WallhavenPage.self, from: data)
    }

    func imageData(from url: URL) async throws -> Data {
        // Only fetch from Wallhaven's own hosts.
        guard let host = url.host, host == "wallhaven.cc" || host.hasSuffix(".wallhaven.cc"), url.scheme == "https" else {
            throw WallhavenError.notAnImage
        }
        let (data, response) = try await session.data(for: request(url))
        try Self.check(response)
        return data
    }

    /// Streams a full wallpaper to a temporary file (the caller deletes it), so it never sits in memory.
    func downloadImage(from url: URL) async throws -> URL {
        guard let host = url.host, host == "wallhaven.cc" || host.hasSuffix(".wallhaven.cc"), url.scheme == "https" else {
            throw WallhavenError.notAnImage
        }
        let (file, response) = try await session.download(for: request(url))
        do { try Self.check(response) } catch { try? FileManager.default.removeItem(at: file); throw error }
        return file
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 429 { throw WallhavenError.rateLimited }
        guard (200..<300).contains(http.statusCode) else {
            throw WallhavenError.badResponse(http.statusCode)
        }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    /// About three pages of results.
    private var recent = RecentImages<URL>(limit: 72)

    func image(for url: URL) -> NSImage? { recent.image(for: url) }
    func store(_ image: NSImage, for url: URL) { recent.store(image, for: url) }
    func removeAll() { recent.removeAll() }
}

enum WallpaperInstaller {
    /// Downloads the full-resolution image into the widget's data directory
    /// and applies it to every screen.
    @MainActor
    static func setDesktop(
        _ wallpaper: Wallpaper,
        client: WallhavenClient,
        directory: URL
    ) async throws {
        let temporary = try await client.downloadImage(from: wallpaper.path)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard ImageDecoder.isImage(temporary) else { throw WallhavenError.notAnImage }
        let folder = directory.appendingPathComponent("Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("wallhaven-\(wallpaper.id).\(wallpaper.path.pathExtension)")
        // Already there when this wallpaper was set before; the desktop may be showing it, so leave it alone.
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.moveItem(at: temporary, to: file)
        }
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [:])
        }
    }
}


/// Where you left off, saved so reopening the Notch brings you back to the same page, search and image.
struct SessionState: Codable, Equatable {
    var text: String
    var sorting: String
    var page: Int
    var seed: String?
    var selected: Wallpaper?
    var showingFavorites: Bool
    var lastViewedID: String?
}

enum PreviewLayout {
    /// The size of the large preview: the image's own shape, as large as fits in `available` (never upscaled
    /// past it, never tiny). Falls back to 16:9 when the resolution can't be read.
    static func size(forResolution resolution: String, in available: CGSize) -> CGSize {
        let parts = resolution.lowercased().split(separator: "x").compactMap { Double($0) }
        let aspect = parts.count == 2 && parts[0] > 0 && parts[1] > 0 ? parts[0] / parts[1] : 16.0 / 9.0
        var width = available.width, height = width / aspect
        if height > available.height { height = available.height; width = height * aspect }
        let floor = 280.0
        if min(width, height) < floor {
            let scale = floor / min(width, height)
            width = min(available.width, width * scale); height = min(available.height, height * scale)
        }
        return CGSize(width: width.rounded(), height: height.rounded())
    }
}
