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

struct WallhavenQuery: Equatable, Sendable {
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

    func search(_ query: WallhavenQuery) async throws -> WallhavenPage {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var items = [
            URLQueryItem(name: "categories", value: "111"),
            URLQueryItem(name: "purity", value: "100"),
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

        let (data, response) = try await session.data(for: request(components.url!))
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
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
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
        let data = try await client.imageData(from: wallpaper.path)
        guard NSImage(data: data) != nil else { throw WallhavenError.notAnImage }
        let folder = directory.appendingPathComponent("Wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("wallhaven-\(wallpaper.id).\(wallpaper.path.pathExtension)")
        try data.write(to: file, options: .atomic)
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(file, for: screen, options: [:])
        }
    }
}
