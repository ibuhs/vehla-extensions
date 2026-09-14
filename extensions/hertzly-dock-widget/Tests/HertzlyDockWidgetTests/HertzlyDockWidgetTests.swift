import Foundation
import XCTest
@testable import HertzlyDockWidget

final class HertzlyDockWidgetTests: XCTestCase {
    func testRadioBrowserRequestUsesExactCountryAndFilters() throws {
        let url = try XCTUnwrap(RadioBrowserClient.requestURL(countryCode: "gb"))
        XCTAssertTrue(url.path.hasSuffix("/bycountrycodeexact/GB"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
        XCTAssertEqual(values["hidebroken"], "true")
        XCTAssertEqual(values["order"], "clickcount")
        XCTAssertEqual(values["reverse"], "true")
    }

    func testRadioStationDecodingMatchesRadioBrowserPayload() throws {
        let json = """
        [{
          "stationuuid":"station-1",
          "name":"Test FM",
          "url_resolved":"https://example.com/live",
          "homepage":"https://example.com",
          "favicon":"",
          "tags":"jazz,local",
          "country":"United States",
          "language":"english",
          "codec":"MP3",
          "bitrate":128
        }]
        """
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8))
        XCTAssertEqual(stations.first?.name, "Test FM")
        XCTAssertEqual(stations.first?.bitrate, 128)
    }

    func testTunerMappingRoundTripsEveryStation() {
        for index in 0..<37 {
            let frequency = TunerMapping.frequency(for: index, stationCount: 37)
            XCTAssertEqual(TunerMapping.stationIndex(for: frequency, stationCount: 37), index)
        }
        XCTAssertEqual(TunerMapping.frequency(for: 0, stationCount: 1), 93.1)
    }

    func testCountryCatalogIncludesPopularCountriesAndFlags() throws {
        let us = try XCTUnwrap(RadioCountry.country(code: "US"))
        XCTAssertEqual(us.flag, "🇺🇸")
        XCTAssertTrue(RadioCountry.popular.contains(us))
    }

    func testRepositoryPersistsPreferencesAndCountryCaches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = HertzlyRepository(directory: directory)
        let station = makeStation()
        let preferences = HertzlyPreferences(
            selectedCountryCode: "CA",
            currentStationID: station.id,
            favoriteStations: [station],
            volume: 0.75
        )

        try await repository.savePreferences(preferences)
        try await repository.saveStations([station], countryCode: "CA")

        let loadedPreferences = try await repository.loadPreferences()
        let canadianStations = try await repository.loadStations(countryCode: "CA")
        let americanStations = try await repository.loadStations(countryCode: "US")
        XCTAssertEqual(loadedPreferences, preferences)
        XCTAssertEqual(canadianStations, [station])
        XCTAssertNil(americanStations)
    }

    private func makeStation() -> RadioStation {
        RadioStation(
            stationuuid: "station-1",
            name: "Test FM",
            url_resolved: "https://example.com/live",
            homepage: "https://example.com",
            favicon: nil,
            tags: "test",
            country: "Canada",
            language: "english",
            codec: "MP3",
            bitrate: 128
        )
    }
}
