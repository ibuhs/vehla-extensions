import Foundation

struct CoverArtResult: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    let year: Int?
    let imageURL: URL
    let width: Int?
    let height: Int?

    var imdbURL: URL {
        URL(string: "https://www.imdb.com/title/\(id)/")!
    }

    var dimensions: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }

    var imageFileName: String {
        let invalid = CharacterSet(charactersIn: "/:\\")
            .union(.controlCharacters)
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Cover Art" : cleaned) + ".jpg"
    }
}

enum CoverArtSearchError: LocalizedError {
    case invalidResponse
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "IMDb returned an unexpected response."
        case .noResults:
            return "No cover art found. Try a broader title."
        }
    }
}

actor CoverArtSearchService {
    static let shared = CoverArtSearchService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(_ query: String) async throws -> [CoverArtResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var components = URLComponents(
            string: "https://v3.sg.media-imdb.com/suggestion/x/\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed).json"
        )
        components?.queryItems = [URLQueryItem(name: "v", value: "1")]
        guard let url = components?.url else { throw CoverArtSearchError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("Vehla Cover Art Search/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CoverArtSearchError.invalidResponse
        }

        let payload = try JSONDecoder().decode(IMDbSuggestionResponse.self, from: data)
        let results = payload.d.compactMap(CoverArtResult.init).filter { $0.imageURL.scheme == "https" }
        guard !results.isEmpty else { throw CoverArtSearchError.noResults }
        return results
    }

    func imageData(for result: CoverArtResult) async throws -> Data {
        let (data, response) = try await session.data(from: result.imageURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw CoverArtSearchError.invalidResponse
        }
        return data
    }
}

private struct IMDbSuggestionResponse: Decodable {
    let d: [IMDbSuggestion]
}

private struct IMDbSuggestion: Decodable {
    let id: String?
    let l: String?
    let s: String?
    let q: String?
    let y: Int?
    let i: IMDbImage?
}

private struct IMDbImage: Decodable {
    let imageURL: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case imageURL = "imageUrl"
        case width
        case height
    }
}

private extension CoverArtResult {
    init?(suggestion: IMDbSuggestion) {
        guard
            let id = suggestion.id,
            id.hasPrefix("tt"),
            let title = suggestion.l,
            let imageString = suggestion.i?.imageURL,
            let imageURL = URL(string: imageString),
            suggestion.q != "tvEpisode"
        else { return nil }

        self.init(
            id: id,
            title: title,
            subtitle: suggestion.s ?? suggestion.q?.replacingOccurrences(of: "tv", with: "TV ").capitalized ?? "Title",
            kind: suggestion.q ?? "Title",
            year: suggestion.y,
            imageURL: imageURL,
            width: suggestion.i?.width,
            height: suggestion.i?.height
        )
    }
}
