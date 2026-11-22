import Foundation

public struct CalendarItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let location: String?
    public let joinURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                location: String? = nil, joinURL: URL? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.location = location; self.joinURL = joinURL
    }

    public func isInProgress(at now: Date) -> Bool { !isAllDay && start <= now && now < end }
}

public struct ReminderItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let due: Date?
    public init(id: String, title: String, due: Date?) { self.id = id; self.title = title; self.due = due }
}

public struct WeatherSnapshot: Equatable, Sendable {
    public let temperatureC: Double
    public let code: Int
    public let highC: Double
    public let lowC: Double
    public let precipitationChance: Int

    public init(temperatureC: Double, code: Int, highC: Double, lowC: Double, precipitationChance: Int) {
        self.temperatureC = temperatureC; self.code = code; self.highC = highC
        self.lowC = lowC; self.precipitationChance = precipitationChance
    }
}

public struct Place: Equatable, Codable, Sendable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name; self.latitude = latitude; self.longitude = longitude
    }
}

public enum Temperature {
    public static func format(_ celsius: Double, fahrenheit: Bool) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
}
