import Foundation

struct ZLibraryBook: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var hash: String?
    var url: String
    var name: String
    var authors: [String]?
    var year: String?
    var extensionName: String?
    var size: String?
    var rating: String?

    enum CodingKeys: String, CodingKey {
        case id, hash, url, name, authors, year, size, rating
        case extensionName = "extension"
    }

    var authorLine: String {
        authors?.joined(separator: ", ") ?? ""
    }

    var webpageURL: URL? {
        guard let value = URL(string: url), value.scheme == "https" || value.scheme == "http" else {
            return nil
        }
        return value
    }
}

struct ZLibrarySearchResponse: Codable, Equatable, Sendable {
    let books: [ZLibraryBook]
    let page: Int
    let totalPages: Int

    enum CodingKeys: String, CodingKey {
        case books, page
        case totalPages = "total_pages"
    }
}

struct ZLibraryQueueItem: Codable, Hashable, Identifiable, Sendable {
    var book: ZLibraryBook
    var downloaded: Bool
    var queuedAt: Date

    var id: String { book.id }
}

struct ZLibrarySettings: Codable, Equatable, Sendable {
    var binaryPath = ""
    var downloadDirectory = "~/Downloads"
    var domainOverride = ""
}

struct ZLibrarySavedState: Codable, Equatable, Sendable {
    var settings = ZLibrarySettings()
    var queue: [ZLibraryQueueItem] = []
}

enum ZLibraryMode: String, CaseIterable, Identifiable {
    case search
    case queue

    var id: String { rawValue }
}

enum ZLibraryError: LocalizedError {
    case cliMissing
    case commandFailed(String)
    case invalidSearchResponse

    var errorDescription: String? {
        switch self {
        case .cliMissing:
            return "The zlib CLI was not found. Install it with Homebrew or choose its path in Settings."
        case .commandFailed(let message):
            return message
        case .invalidSearchResponse:
            return "The zlib CLI returned an unreadable search response."
        }
    }
}
