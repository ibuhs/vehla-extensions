import AppKit
import Foundation
import ImageIO

actor NewsRepository {
    private let dataDirectory: URL
    private let stateURL: URL

    init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory
        stateURL = dataDirectory.appendingPathComponent("news-state.json")
    }

    func load() throws -> NewsSavedState {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return NewsSavedState(
                feeds: NewsDefaults.starterFeeds,
                items: [],
                readIDs: [],
                lastRefreshAt: nil
            )
        }
        let data = try Data(contentsOf: stateURL)
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NewsSavedState.self, from: data)
    }

    func save(_ state: NewsSavedState) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try Task.checkCancellation()
        try data.write(to: stateURL, options: .atomic)
    }
}

actor FeedFetcher {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = NewsDefaults.requestTimeout
        configuration.timeoutIntervalForResource = NewsDefaults.requestTimeout + 15
        configuration.httpAdditionalHeaders = [
            "Accept": "application/rss+xml, application/atom+xml, application/xml, text/xml, */*",
            "User-Agent": "VehlaNewsDockWidget/1.0",
        ]
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func fetchDocument(
        from url: URL,
        itemLimit: Int = NewsDefaults.maxItemsPerFeed
    ) async throws -> ParsedFeedDocument {
        try Task.checkCancellation()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = NewsDefaults.requestTimeout

        let (bytes, response) = try await session.bytes(for: request)
        try Task.checkCancellation()

        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw NewsFetchError.httpStatus(http.statusCode)
        }

        var data = Data()
        data.reserveCapacity(256_000)
        var pending = Data()
        pending.reserveCapacity(32_768)

        for try await byte in bytes {
            try Task.checkCancellation()
            pending.append(byte)
            if pending.count >= 32_768 {
                data.append(pending)
                pending.removeAll(keepingCapacity: true)
                if data.count > NewsDefaults.maxFeedBytes {
                    throw NewsFetchError.tooLarge
                }
                if let truncated = FeedEarlyExit.truncatedData(
                    from: data,
                    itemLimit: itemLimit
                ) {
                    return try FeedParser.parse(data: truncated, itemLimit: itemLimit)
                }
            }
        }

        data.append(pending)
        guard !data.isEmpty else { throw NewsFetchError.emptyResponse }
        guard data.count <= NewsDefaults.maxFeedBytes else {
            throw NewsFetchError.tooLarge
        }
        if let truncated = FeedEarlyExit.truncatedData(from: data, itemLimit: itemLimit) {
            return try FeedParser.parse(data: truncated, itemLimit: itemLimit)
        }
        return try FeedParser.parse(data: data, itemLimit: itemLimit)
    }

    func refresh(
        feeds: [NewsFeed],
        existingItems: [NewsItem],
        onlyFeedIDs: Set<String>? = nil
    ) async -> (items: [NewsItem], feedUpdates: [NewsFeed], errors: [String]) {
        let targets = feeds.filter { feed in
            guard feed.isEnabled else { return false }
            if let onlyFeedIDs { return onlyFeedIDs.contains(feed.id) }
            return !feed.isMuted
        }

        var mergedByID = Dictionary(
            uniqueKeysWithValues: existingItems.map { ($0.id, $0) }
        )
        // Drop items for feeds we are about to refresh so stale episodes go away.
        if let onlyFeedIDs {
            mergedByID = mergedByID.filter { !onlyFeedIDs.contains($0.value.feedID) }
                .reduce(into: [:]) { $0[$1.key] = $1.value }
        } else {
            let targetIDs = Set(targets.map(\.id))
            mergedByID = mergedByID.filter { !targetIDs.contains($0.value.feedID) }
                .reduce(into: [:]) { $0[$1.key] = $1.value }
        }

        var feedUpdates: [String: NewsFeed] = [:]
        var errors: [String] = []
        let fetchedAt = Date()

        await withTaskGroup(of: FeedRefreshResult.self) { group in
            var inFlight = 0
            var iterator = targets.makeIterator()

            func enqueueNext() {
                while inFlight < 3, let feed = iterator.next() {
                    inFlight += 1
                    group.addTask { [self] in
                        await self.refreshOne(feed: feed)
                    }
                }
            }

            enqueueNext()
            for await result in group {
                inFlight -= 1
                switch result {
                case .success(let feed, let document):
                    var updated = feed
                    if let title = document.title, !title.isEmpty {
                        updated.title = title
                    }
                    if let site = document.siteURLString, !site.isEmpty {
                        updated.siteURLString = site
                    }
                    if let art = document.artworkURLString, !art.isEmpty {
                        updated.artworkURLString = art
                    }
                    if updated.refreshIntervalSeconds == NewsDefaults.defaultRefreshSeconds,
                       NewsDefaults.inferredRefreshSeconds(for: updated.urlString)
                        == NewsDefaults.podcastRefreshSeconds {
                        updated.refreshIntervalSeconds = NewsDefaults.podcastRefreshSeconds
                    }
                    updated.lastFetchedAt = fetchedAt
                    feedUpdates[feed.id] = updated

                    for parsed in document.items.prefix(NewsDefaults.maxItemsPerFeed) {
                        let item = makeItem(
                            from: parsed,
                            feed: updated,
                            fetchedAt: fetchedAt
                        )
                        mergedByID[item.id] = item
                    }
                case .failure(let feed, let message):
                    var updated = feed
                    updated.lastFetchedAt = fetchedAt
                    feedUpdates[feed.id] = updated
                    errors.append("\(feed.title): \(message)")
                }
                enqueueNext()
            }
        }

        let sorted = mergedByID.values.sorted { lhs, rhs in
            let left = lhs.publishedAt ?? lhs.fetchedAt
            let right = rhs.publishedAt ?? rhs.fetchedAt
            if left != right { return left > right }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        let trimmed = Array(sorted.prefix(NewsDefaults.maxCachedItems))
        let updatedFeeds = feeds.map { feedUpdates[$0.id] ?? $0 }
        return (trimmed, updatedFeeds, errors)
    }

    private func refreshOne(feed: NewsFeed) async -> FeedRefreshResult {
        guard let url = feed.feedURL else {
            return .failure(feed, NewsFetchError.invalidURL.localizedDescription)
        }
        do {
            try Task.checkCancellation()
            let document = try await fetchDocument(from: url)
            return .success(feed, document)
        } catch is CancellationError {
            return .failure(feed, "Cancelled")
        } catch {
            return .failure(
                feed,
                (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            )
        }
    }

    private func makeItem(
        from parsed: ParsedFeedItem,
        feed: NewsFeed,
        fetchedAt: Date
    ) -> NewsItem {
        let stableKey = parsed.guid?.nilIfEmpty
            ?? parsed.linkString.nilIfEmpty
            ?? "\(feed.id)|\(parsed.title)|\(parsed.publishedAt?.timeIntervalSince1970 ?? 0)"
        let id = "\(feed.id)|\(stableKey)".stableHashHex
        return NewsItem(
            id: id,
            feedID: feed.id,
            feedTitle: feed.title,
            title: parsed.title,
            summary: String(parsed.summary.prefix(1_200)),
            linkString: parsed.linkString,
            author: parsed.author,
            publishedAt: parsed.publishedAt,
            fetchedAt: fetchedAt
        )
    }
}

actor FeedIconCache {
    private let directory: URL
    private let session: URLSession
    private var memory: [String: CGImage] = [:]

    init(dataDirectory: URL) {
        directory = dataDirectory.appendingPathComponent(
            "FeedIconCache",
            isDirectory: true
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpAdditionalHeaders = [
            "User-Agent": "VehlaNewsDockWidget/1.0",
        ]
        session = URLSession(configuration: configuration)
    }

    func image(for feed: NewsFeed) async -> CGImage? {
        let key = cacheKey(for: feed)
        if let cached = memory[key] { return cached }

        let fileURL = cacheURL(for: key)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let image = thumbnail(from: data) {
            memory[key] = image
            return image
        }

        guard let data = await downloadIconData(for: feed) else { return nil }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
        let image = thumbnail(from: data)
        memory[key] = image
        return image
    }

    private func downloadIconData(for feed: NewsFeed) async -> Data? {
        var candidates: [URL] = []
        if let artwork = feed.artworkURL {
            candidates.append(artwork)
        }
        if let host = feed.siteURL?.host ?? feed.feedURL?.host {
            if let favicon = URL(string: "https://\(host)/favicon.ico") {
                candidates.append(favicon)
            }
            if let duck = URL(
                string: "https://icons.duckduckgo.com/ip3/\(host).ico"
            ) {
                candidates.append(duck)
            }
        }

        for url in candidates {
            do {
                try Task.checkCancellation()
                var request = URLRequest(url: url)
                request.timeoutInterval = 12
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode),
                      !data.isEmpty,
                      data.count <= NewsDefaults.maxIconBytes,
                      thumbnail(from: data) != nil else {
                    continue
                }
                return data
            } catch {
                continue
            }
        }
        return nil
    }

    private func thumbnail(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func cacheKey(for feed: NewsFeed) -> String {
        let art = feed.artworkURLString ?? ""
        return "\(feed.id)|\(art)|\(feed.siteURLString ?? "")"
    }

    private func cacheURL(for key: String) -> URL {
        let hash = key.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".icon")
    }
}

enum OPMLDocument {
    static func export(feeds: [NewsFeed]) -> String {
        let escapedTitle = xmlEscape("Vehla News Feeds")
        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>\(escapedTitle)</title>",
            "    <dateCreated>\(RFC822.string(from: Date()))</dateCreated>",
            "  </head>",
            "  <body>",
        ]
        for feed in feeds.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let text = xmlEscape(feed.title)
            let xmlURL = xmlEscape(feed.urlString)
            let html = xmlEscape(feed.siteURLString ?? "")
            var attrs = #"text="\#(text)" title="\#(text)" type="rss" xmlUrl="\#(xmlURL)""#
            if !html.isEmpty {
                attrs += #" htmlUrl="\#(html)""#
            }
            lines.append("    <outline \(attrs) />")
        }
        lines.append(contentsOf: ["  </body>", "</opml>", ""])
        return lines.joined(separator: "\n")
    }

    static func parse(_ data: Data) throws -> [NewsFeed] {
        let delegate = OPMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw NewsFetchError.parseFailed(
                parser.parserError?.localizedDescription ?? "OPML"
            )
        }
        guard !delegate.feeds.isEmpty else {
            throw NewsFetchError.parseFailed("No feeds found in OPML.")
        }
        return delegate.feeds
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private enum RFC822 {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var feeds: [NewsFeed] = []
    private var sortOrder = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        let xmlURL = attributeDict["xmlUrl"]
            ?? attributeDict["xmlurl"]
            ?? attributeDict["XMLURL"]
        guard let xmlURL, !xmlURL.isEmpty else { return }
        let title = attributeDict["title"]
            ?? attributeDict["text"]
            ?? URL(string: xmlURL)?.host
            ?? "Feed"
        let html = attributeDict["htmlUrl"] ?? attributeDict["htmlurl"]
        feeds.append(
            NewsFeed(
                title: title,
                urlString: xmlURL,
                siteURLString: html,
                refreshIntervalSeconds: NewsDefaults.inferredRefreshSeconds(
                    for: xmlURL
                ),
                sortOrder: sortOrder
            )
        )
        sortOrder += 1
    }
}

private enum FeedRefreshResult: Sendable {
    case success(NewsFeed, ParsedFeedDocument)
    case failure(NewsFeed, String)
}

extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }

    var stableHashHex: String {
        var hash: UInt64 = 14695981039346656037
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        var hash2: UInt64 = 2166136261
        for byte in utf8.reversed() {
            hash2 ^= UInt64(byte)
            hash2 &*= 16777619
        }
        return String(format: "%016llx%016llx", hash, hash2)
    }
}
