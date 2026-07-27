import Foundation

enum FeedRefreshInterval: Int, Codable, CaseIterable, Sendable, Identifiable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case hourly = 3600
    case sixHours = 21_600
    case daily = 86_400

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .fiveMinutes: return "5 min"
        case .fifteenMinutes: return "15 min"
        case .hourly: return "1 hour"
        case .sixHours: return "6 hours"
        case .daily: return "Daily"
        }
    }

    static func coerce(_ seconds: Int) -> FeedRefreshInterval {
        allCases.min(by: {
            abs($0.rawValue - seconds) < abs($1.rawValue - seconds)
        }) ?? .fiveMinutes
    }
}

struct NewsFeed: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    var urlString: String
    var siteURLString: String?
    var artworkURLString: String?
    var isEnabled: Bool
    var isMuted: Bool
    var refreshIntervalSeconds: Int
    var lastFetchedAt: Date?
    var sortOrder: Int

    var feedURL: URL? { URL(string: urlString) }
    var siteURL: URL? {
        siteURLString.flatMap(URL.init(string:))
    }
    var artworkURL: URL? {
        artworkURLString.flatMap(URL.init(string:))
    }
    var refreshInterval: FeedRefreshInterval {
        get { FeedRefreshInterval.coerce(refreshIntervalSeconds) }
        set { refreshIntervalSeconds = newValue.rawValue }
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        urlString: String,
        siteURLString: String? = nil,
        artworkURLString: String? = nil,
        isEnabled: Bool = true,
        isMuted: Bool = false,
        refreshIntervalSeconds: Int = NewsDefaults.defaultRefreshSeconds,
        lastFetchedAt: Date? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.siteURLString = siteURLString
        self.artworkURLString = artworkURLString
        self.isEnabled = isEnabled
        self.isMuted = isMuted
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.lastFetchedAt = lastFetchedAt
        self.sortOrder = sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decode(String.self, forKey: .urlString)
        siteURLString = try container.decodeIfPresent(String.self, forKey: .siteURLString)
        artworkURLString = try container.decodeIfPresent(String.self, forKey: .artworkURLString)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        refreshIntervalSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .refreshIntervalSeconds
        ) ?? NewsDefaults.defaultRefreshSeconds
        lastFetchedAt = try container.decodeIfPresent(Date.self, forKey: .lastFetchedAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }

    func isDue(at date: Date = Date()) -> Bool {
        guard isEnabled, !isMuted else { return false }
        guard let lastFetchedAt else { return true }
        return date.timeIntervalSince(lastFetchedAt) >= TimeInterval(refreshIntervalSeconds)
    }
}

struct NewsItem: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var feedID: String
    var feedTitle: String
    var title: String
    var summary: String
    var linkString: String
    var author: String?
    var publishedAt: Date?
    var fetchedAt: Date

    var linkURL: URL? { URL(string: linkString) }

    func matches(_ query: String) -> Bool {
        query.isEmpty
            || title.localizedCaseInsensitiveContains(query)
            || summary.localizedCaseInsensitiveContains(query)
            || feedTitle.localizedCaseInsensitiveContains(query)
            || (author?.localizedCaseInsensitiveContains(query) ?? false)
    }
}

struct NewsSavedState: Codable, Sendable {
    var feeds: [NewsFeed]
    var items: [NewsItem]
    var readIDs: [String]
    var lastRefreshAt: Date?
}

struct ParsedFeedDocument: Sendable {
    var title: String?
    var siteURLString: String?
    var artworkURLString: String?
    var items: [ParsedFeedItem]
}

struct ParsedFeedItem: Sendable {
    var title: String
    var summary: String
    var linkString: String
    var author: String?
    var publishedAt: Date?
    var guid: String?
}

enum NewsFetchError: Error, LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case emptyResponse
    case tooLarge
    case parseFailed(String)
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid feed URL."
        case .httpStatus(let code):
            return "Feed returned HTTP \(code)."
        case .emptyResponse:
            return "Feed was empty."
        case .tooLarge:
            return "Feed is too large (over 12 MB)."
        case .parseFailed(let detail):
            return "Could not parse feed (\(detail))."
        case .unsupportedFormat:
            return "Unsupported feed format."
        }
    }
}

enum NewsDefaults {
    static let maxItemsPerFeed = 40
    static let maxCachedItems = 400
    /// Hard ceiling while streaming; early-exit usually stops much sooner.
    static let maxFeedBytes = 12_000_000
    static let pollTick: Duration = .seconds(60)
    static let defaultRefreshSeconds = FeedRefreshInterval.fiveMinutes.rawValue
    static let podcastRefreshSeconds = FeedRefreshInterval.hourly.rawValue
    static let requestTimeout: TimeInterval = 45
    static let maxIconBytes = 2_000_000

    static let starterFeeds: [NewsFeed] = [
        NewsFeed(
            title: "Apple Newsroom",
            urlString: "https://www.apple.com/newsroom/rss-feed.rss",
            siteURLString: "https://www.apple.com/newsroom/",
            sortOrder: 0
        ),
        NewsFeed(
            title: "BBC World",
            urlString: "https://feeds.bbci.co.uk/news/world/rss.xml",
            siteURLString: "https://www.bbc.com/news/world",
            sortOrder: 1
        ),
        NewsFeed(
            title: "NPR News",
            urlString: "https://feeds.npr.org/1001/rss.xml",
            siteURLString: "https://www.npr.org/",
            sortOrder: 2
        ),
        NewsFeed(
            title: "The Verge",
            urlString: "https://www.theverge.com/rss/index.xml",
            siteURLString: "https://www.theverge.com/",
            sortOrder: 3
        ),
        NewsFeed(
            title: "Hacker News",
            urlString: "https://hnrss.org/frontpage",
            siteURLString: "https://news.ycombinator.com/",
            sortOrder: 4
        ),
    ]

    static func inferredRefreshSeconds(for urlString: String) -> Int {
        let lowered = urlString.lowercased()
        if lowered.contains("simplecast")
            || lowered.contains("podcast")
            || lowered.contains("anchor.fm")
            || lowered.contains("transistor.fm")
            || lowered.contains("megaphone.fm")
            || lowered.contains("libsyn") {
            return podcastRefreshSeconds
        }
        return defaultRefreshSeconds
    }
}
