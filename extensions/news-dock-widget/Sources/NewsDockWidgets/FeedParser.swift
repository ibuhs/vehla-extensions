import Foundation

enum FeedParser {
    static func parse(
        data: Data,
        itemLimit: Int = NewsDefaults.maxItemsPerFeed
    ) throws -> ParsedFeedDocument {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw NewsFetchError.emptyResponse }

        let probe = String(decoding: data.prefix(2_048), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if probe.contains("<rss") || probe.contains("<rdf:rdf") {
            return try parseRSS(data, itemLimit: itemLimit)
        }
        if probe.contains("<feed") {
            return try parseAtom(data, itemLimit: itemLimit)
        }

        if let rss = try? parseRSS(data, itemLimit: itemLimit), !rss.items.isEmpty {
            return rss
        }
        if let atom = try? parseAtom(data, itemLimit: itemLimit), !atom.items.isEmpty {
            return atom
        }
        throw NewsFetchError.unsupportedFormat
    }

    private static func parseRSS(_ data: Data, itemLimit: Int) throws -> ParsedFeedDocument {
        let delegate = RSSParserDelegate(itemLimit: itemLimit)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() || !delegate.document.items.isEmpty else {
            let detail = parser.parserError?.localizedDescription ?? "RSS"
            throw NewsFetchError.parseFailed(detail)
        }
        try Task.checkCancellation()
        return delegate.document
    }

    private static func parseAtom(_ data: Data, itemLimit: Int) throws -> ParsedFeedDocument {
        let delegate = AtomParserDelegate(itemLimit: itemLimit)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() || !delegate.document.items.isEmpty else {
            let detail = parser.parserError?.localizedDescription ?? "Atom"
            throw NewsFetchError.parseFailed(detail)
        }
        try Task.checkCancellation()
        return delegate.document
    }
}

/// Truncates a partially downloaded feed after `itemLimit` items so large
/// podcast XML can be parsed without downloading the entire document.
enum FeedEarlyExit {
    static func truncatedData(
        from data: Data,
        itemLimit: Int
    ) -> Data? {
        guard itemLimit > 0,
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        let lower = text.lowercased()
        var search = lower.startIndex
        var closed = 0
        var cut: String.Index?

        while closed < itemLimit, search < lower.endIndex {
            let itemRange = lower.range(of: "</item>", range: search..<lower.endIndex)
            let entryRange = lower.range(of: "</entry>", range: search..<lower.endIndex)
            let next: Range<String.Index>?
            switch (itemRange, entryRange) {
            case let (item?, entry?):
                next = item.lowerBound < entry.lowerBound ? item : entry
            case let (item?, nil):
                next = item
            case let (nil, entry?):
                next = entry
            case (nil, nil):
                next = nil
            }
            guard let next else { return nil }
            closed += 1
            cut = next.upperBound
            search = next.upperBound
        }

        guard closed >= itemLimit, let cut else { return nil }
        var prefix = String(text[..<cut])
        if lower.contains("<rss") || lower.contains("<rdf:rdf") {
            if !lower[..<cut].contains("</channel>") {
                prefix += "\n</channel></rss>"
            }
        } else if lower.contains("<feed"), !lower[..<cut].contains("</feed>") {
            prefix += "\n</feed>"
        }
        return prefix.data(using: .utf8)
    }
}

// MARK: - Shared helpers

private enum FeedDateParser {
    private static let formats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd HH:mm:ss Z",
        "yyyy-MM-dd",
    ]

    static func parse(_ raw: String?) -> Date? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: trimmed) { return date }

        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

private enum HTMLText {
    static func plain(_ raw: String?) -> String {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return ""
        }

        text = text.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"</p\s*>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )

        let entities: [String: String] = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&nbsp;": " ",
            "&#x27;": "'",
            "&#8217;": "’",
            "&#8216;": "‘",
            "&#8220;": "“",
            "&#8221;": "”",
            "&rsquo;": "’",
            "&lsquo;": "‘",
            "&rdquo;": "”",
            "&ldquo;": "“",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…",
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = text.replacingOccurrences(
            of: #"&#(\d+);"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"&#x([0-9a-fA-F]+);"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func localName(_ elementName: String) -> String {
    if let index = elementName.lastIndex(of: ":") {
        return String(elementName[elementName.index(after: index)...]).lowercased()
    }
    return elementName.lowercased()
}

// MARK: - RSS

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    private let itemLimit: Int
    private(set) var document = ParsedFeedDocument(
        title: nil,
        siteURLString: nil,
        artworkURLString: nil,
        items: []
    )

    private var path: [String] = []
    private var textBuffer = ""
    private var inItem = false
    private var inImage = false
    private var itemTitle = ""
    private var itemSummary = ""
    private var itemLink = ""
    private var itemAuthor = ""
    private var itemDate = ""
    private var itemGUID = ""
    private var channelTitle = ""
    private var channelLink = ""
    private var channelImageURL = ""
    private var didAbort = false

    init(itemLimit: Int) {
        self.itemLimit = itemLimit
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !didAbort else { return }
        let name = localName(elementName)
        path.append(name)
        textBuffer = ""

        if name == "item" || name == "entry" {
            inItem = true
            itemTitle = ""
            itemSummary = ""
            itemLink = ""
            itemAuthor = ""
            itemDate = ""
            itemGUID = ""
        }
        if !inItem, name == "image" {
            inImage = true
        }
        if !inItem {
            if name == "image",
               let href = attributeDict["href"] ?? attributeDict["url"],
               channelImageURL.isEmpty {
                channelImageURL = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !didAbort else { return }
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !didAbort else { return }
        if let string = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard !didAbort else { return }
        let name = localName(elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !path.isEmpty { path.removeLast() }
            textBuffer = ""
        }

        if inItem {
            switch name {
            case "title":
                itemTitle = HTMLText.plain(value)
            case "description", "summary", "content", "encoded":
                if itemSummary.isEmpty || name == "encoded" || name == "content" {
                    itemSummary = HTMLText.plain(value)
                }
            case "link":
                if itemLink.isEmpty { itemLink = value }
            case "author", "creator":
                itemAuthor = HTMLText.plain(value)
            case "pubdate", "published", "updated", "date":
                if itemDate.isEmpty { itemDate = value }
            case "guid", "id":
                itemGUID = value
            case "item", "entry":
                finishItem()
                inItem = false
                if document.items.count >= itemLimit {
                    didAbort = true
                    parser.abortParsing()
                }
            default:
                break
            }
            return
        }

        if inImage, name == "url", channelImageURL.isEmpty {
            channelImageURL = value
        }
        if name == "image" {
            inImage = false
        }

        switch name {
        case "title" where channelTitle.isEmpty:
            channelTitle = HTMLText.plain(value)
        case "link" where channelLink.isEmpty:
            channelLink = value
        case "channel", "rss", "rdf":
            document.title = channelTitle.isEmpty ? document.title : channelTitle
            document.siteURLString = channelLink.isEmpty ? document.siteURLString : channelLink
            document.artworkURLString = channelImageURL.isEmpty
                ? document.artworkURLString
                : channelImageURL
        default:
            break
        }
    }

    private func finishItem() {
        let title = itemTitle.isEmpty ? "Untitled" : itemTitle
        let link = itemLink
        guard !link.isEmpty || !itemGUID.isEmpty else { return }
        document.items.append(
            ParsedFeedItem(
                title: title,
                summary: itemSummary,
                linkString: link.isEmpty ? itemGUID : link,
                author: itemAuthor.isEmpty ? nil : itemAuthor,
                publishedAt: FeedDateParser.parse(itemDate),
                guid: itemGUID.isEmpty ? nil : itemGUID
            )
        )
        document.title = channelTitle.isEmpty ? document.title : channelTitle
        document.siteURLString = channelLink.isEmpty ? document.siteURLString : channelLink
        document.artworkURLString = channelImageURL.isEmpty
            ? document.artworkURLString
            : channelImageURL
    }
}

// MARK: - Atom

private final class AtomParserDelegate: NSObject, XMLParserDelegate {
    private let itemLimit: Int
    private(set) var document = ParsedFeedDocument(
        title: nil,
        siteURLString: nil,
        artworkURLString: nil,
        items: []
    )

    private var path: [String] = []
    private var textBuffer = ""
    private var inEntry = false
    private var entryTitle = ""
    private var entrySummary = ""
    private var entryLink = ""
    private var entryAuthor = ""
    private var entryDate = ""
    private var entryID = ""
    private var feedTitle = ""
    private var feedLink = ""
    private var feedIcon = ""
    private var linkRel = ""
    private var linkHref = ""
    private var inAuthor = false
    private var didAbort = false

    init(itemLimit: Int) {
        self.itemLimit = itemLimit
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !didAbort else { return }
        let name = localName(elementName)
        path.append(name)
        textBuffer = ""

        if name == "entry" {
            inEntry = true
            entryTitle = ""
            entrySummary = ""
            entryLink = ""
            entryAuthor = ""
            entryDate = ""
            entryID = ""
        }
        if name == "author" {
            inAuthor = true
        }
        if name == "link" {
            linkRel = (attributeDict["rel"] ?? "alternate").lowercased()
            linkHref = attributeDict["href"] ?? ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !didAbort else { return }
        textBuffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !didAbort else { return }
        if let string = String(data: CDATABlock, encoding: .utf8) {
            textBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard !didAbort else { return }
        let name = localName(elementName)
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            if !path.isEmpty { path.removeLast() }
            textBuffer = ""
        }

        if name == "link" {
            let preferred =
                linkRel == "alternate"
                || linkRel.isEmpty
                || linkRel == "self" && !inEntry
            if preferred, !linkHref.isEmpty {
                if inEntry, entryLink.isEmpty {
                    entryLink = linkHref
                } else if !inEntry, feedLink.isEmpty || linkRel == "alternate" {
                    feedLink = linkHref
                }
            } else if inEntry, entryLink.isEmpty, !linkHref.isEmpty {
                entryLink = linkHref
            } else if !inEntry, linkRel == "icon" || linkRel == "image", feedIcon.isEmpty {
                feedIcon = linkHref
            }
            return
        }

        if inEntry {
            switch name {
            case "title":
                entryTitle = HTMLText.plain(value)
            case "summary", "content":
                if entrySummary.isEmpty || name == "content" {
                    entrySummary = HTMLText.plain(value)
                }
            case "name" where inAuthor:
                entryAuthor = HTMLText.plain(value)
            case "author":
                inAuthor = false
            case "published":
                entryDate = value
            case "updated" where entryDate.isEmpty:
                entryDate = value
            case "id":
                entryID = value
            case "entry":
                finishEntry()
                inEntry = false
                if document.items.count >= itemLimit {
                    didAbort = true
                    parser.abortParsing()
                }
            default:
                break
            }
            return
        }

        switch name {
        case "title" where feedTitle.isEmpty:
            feedTitle = HTMLText.plain(value)
        case "icon" where feedIcon.isEmpty:
            feedIcon = value
        case "logo" where feedIcon.isEmpty:
            feedIcon = value
        case "feed":
            document.title = feedTitle.isEmpty ? document.title : feedTitle
            document.siteURLString = feedLink.isEmpty ? document.siteURLString : feedLink
            document.artworkURLString = feedIcon.isEmpty ? document.artworkURLString : feedIcon
        default:
            break
        }
    }

    private func finishEntry() {
        let title = entryTitle.isEmpty ? "Untitled" : entryTitle
        let link = entryLink.isEmpty ? entryID : entryLink
        guard !link.isEmpty else { return }
        document.items.append(
            ParsedFeedItem(
                title: title,
                summary: entrySummary,
                linkString: link,
                author: entryAuthor.isEmpty ? nil : entryAuthor,
                publishedAt: FeedDateParser.parse(entryDate),
                guid: entryID.isEmpty ? nil : entryID
            )
        )
        document.title = feedTitle.isEmpty ? document.title : feedTitle
        document.siteURLString = feedLink.isEmpty ? document.siteURLString : feedLink
        document.artworkURLString = feedIcon.isEmpty ? document.artworkURLString : feedIcon
    }
}
