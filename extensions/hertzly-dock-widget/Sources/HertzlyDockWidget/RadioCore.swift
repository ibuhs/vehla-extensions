import Foundation

struct RadioStation: Codable, Identifiable, Equatable, Sendable {
    var id: String { stationuuid }

    let stationuuid: String
    let name: String
    let url_resolved: String
    let homepage: String?
    let favicon: String?
    let tags: String
    let country: String
    let language: String
    let codec: String
    let bitrate: Int
}

struct RadioCountry: Identifiable, Equatable, Sendable {
    let code: String
    let name: String

    var id: String { code }

    var flag: String {
        code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127_397 + $0.value).map(String.init)
        }.joined()
    }

    static let popularCodes = ["US", "GB", "CA", "AU", "IN", "DE", "FR", "JP", "BR", "MX", "ES", "IT"]

    static let all: [RadioCountry] = Locale.Region.isoRegions.compactMap { region in
        let code = region.identifier.uppercased()
        guard code.count == 2,
              let name = Locale.current.localizedString(forRegionCode: code)
        else { return nil }
        return RadioCountry(code: code, name: name)
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    static var popular: [RadioCountry] {
        popularCodes.compactMap { code in all.first { $0.code == code } }
    }

    static func country(code: String) -> RadioCountry? {
        all.first { $0.code == code.uppercased() }
    }
}

enum TunerMapping {
    static let range = 87.5...108.0

    static func frequency(for index: Int, stationCount: Int) -> Double {
        guard stationCount > 1 else { return 93.1 }
        let safeIndex = min(max(index, 0), stationCount - 1)
        return range.lowerBound
            + Double(safeIndex) * (range.upperBound - range.lowerBound) / Double(stationCount - 1)
    }

    static func stationIndex(for frequency: Double, stationCount: Int) -> Int {
        guard stationCount > 1 else { return 0 }
        let bounded = min(max(frequency, range.lowerBound), range.upperBound)
        let ratio = (bounded - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(max(Int((ratio * Double(stationCount - 1)).rounded()), 0), stationCount - 1)
    }
}

struct HertzlyPreferences: Codable, Equatable, Sendable {
    var selectedCountryCode = "US"
    var currentStationID: String?
    var favoriteStations: [RadioStation] = []
    var volume: Float = 1
}

actor HertzlyRepository {
    private let directory: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(directory: URL) {
        self.directory = directory
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadPreferences() throws -> HertzlyPreferences {
        try ensureDirectory()
        let url = directory.appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return HertzlyPreferences()
        }
        return try decoder.decode(HertzlyPreferences.self, from: Data(contentsOf: url))
    }

    func savePreferences(_ preferences: HertzlyPreferences) throws {
        try ensureDirectory()
        try encoder.encode(preferences).write(
            to: directory.appendingPathComponent("preferences.json"),
            options: .atomic
        )
    }

    func loadStations(countryCode: String) throws -> [RadioStation]? {
        try ensureDirectory()
        let url = cacheURL(countryCode: countryCode)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder.decode([RadioStation].self, from: Data(contentsOf: url))
    }

    func saveStations(_ stations: [RadioStation], countryCode: String) throws {
        try ensureDirectory()
        try encoder.encode(stations).write(to: cacheURL(countryCode: countryCode), options: .atomic)
    }

    private func cacheURL(countryCode: String) -> URL {
        directory.appendingPathComponent("stations-\(countryCode.uppercased()).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

enum RadioBrowserError: LocalizedError {
    case invalidCountry
    case invalidResponse
    case noStations

    var errorDescription: String? {
        switch self {
        case .invalidCountry: "That country is not available."
        case .invalidResponse: "Radio Browser returned an invalid response."
        case .noStations: "No stations are available for this country."
        }
    }
}

struct RadioBrowserClient: Sendable {
    static func requestURL(countryCode: String) -> URL? {
        let code = countryCode.uppercased()
        guard code.count == 2 else { return nil }
        var components = URLComponents(
            string: "https://de2.api.radio-browser.info/json/stations/bycountrycodeexact/\(code)"
        )
        components?.queryItems = [
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        return components?.url
    }

    func fetchStations(countryCode: String) async throws -> [RadioStation] {
        guard let url = Self.requestURL(countryCode: countryCode) else {
            throw RadioBrowserError.invalidCountry
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Hertzly/1.0 (Vehla Dock Widget)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw RadioBrowserError.invalidResponse
        }
        let stations = try JSONDecoder().decode([RadioStation].self, from: data)
            .filter { URL(string: $0.url_resolved) != nil }
        guard !stations.isEmpty else { throw RadioBrowserError.noStations }
        return stations
    }
}
