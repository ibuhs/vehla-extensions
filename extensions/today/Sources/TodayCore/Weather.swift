import Foundation

public struct WeatherCondition: Equatable, Sendable {
    public let summary: String
    public let symbol: String
    public let isWet: Bool

    /// WMO weather interpretation codes, as returned by Open-Meteo.
    public static func forCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0: return .init(summary: "Clear", symbol: "sun.max.fill", isWet: false)
        case 1: return .init(summary: "Mostly clear", symbol: "sun.max.fill", isWet: false)
        case 2: return .init(summary: "Partly cloudy", symbol: "cloud.sun.fill", isWet: false)
        case 3: return .init(summary: "Overcast", symbol: "cloud.fill", isWet: false)
        case 45, 48: return .init(summary: "Foggy", symbol: "cloud.fog.fill", isWet: false)
        case 51...57: return .init(summary: "Drizzle", symbol: "cloud.drizzle.fill", isWet: true)
        case 61...67: return .init(summary: "Rain", symbol: "cloud.rain.fill", isWet: true)
        case 71...77, 85, 86: return .init(summary: "Snow", symbol: "cloud.snow.fill", isWet: true)
        case 80...82: return .init(summary: "Showers", symbol: "cloud.heavyrain.fill", isWet: true)
        case 95...99: return .init(summary: "Thunderstorms", symbol: "cloud.bolt.rain.fill", isWet: true)
        default: return .init(summary: "Unsettled", symbol: "cloud.fill", isWet: false)
        }
    }
}

public enum WeatherError: Error, LocalizedError {
    case badResponse, noResults
    public var errorDescription: String? {
        switch self {
        case .badResponse: return "Weather service returned something unexpected."
        case .noResults: return "No place found with that name."
        }
    }
}

public enum OpenMeteo {
    public static func forecastURL(for place: Place) -> URL {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return c.url!
    }

    public static func geocodeURL(for name: String) -> URL {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
        ]
        return c.url!
    }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let precipitation_probability_max: [Int?]?
        }
        let current: Current
        let daily: Daily
    }

    public static func parseForecast(_ data: Data) throws -> WeatherSnapshot {
        guard let f = try? JSONDecoder().decode(Forecast.self, from: data) else { throw WeatherError.badResponse }
        return WeatherSnapshot(
            temperatureC: f.current.temperature_2m, code: f.current.weather_code,
            highC: f.daily.temperature_2m_max.first.flatMap { $0 } ?? f.current.temperature_2m,
            lowC: f.daily.temperature_2m_min.first.flatMap { $0 } ?? f.current.temperature_2m,
            precipitationChance: f.daily.precipitation_probability_max?.first.flatMap { $0 } ?? 0)
    }

    private struct Geocode: Decodable {
        struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String? }
        let results: [Result]?
    }

    public static func parseGeocode(_ data: Data) throws -> Place {
        guard let g = try? JSONDecoder().decode(Geocode.self, from: data) else { throw WeatherError.badResponse }
        guard let r = g.results?.first else { throw WeatherError.noResults }
        return Place(name: r.name, latitude: r.latitude, longitude: r.longitude)
    }
}
