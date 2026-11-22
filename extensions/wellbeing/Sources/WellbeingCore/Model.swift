import Foundation

public struct WaterEntry: Codable, Equatable, Sendable {
    public var time: Date
    public var ml: Int
    public init(time: Date, ml: Int) { self.time = time; self.ml = ml }
}

public struct DayLog: Codable, Equatable, Sendable {
    public var water: [WaterEntry] = []
    public var mindfulSeconds = 0
    public var sessions = 0
    public init() {}

    public var waterML: Int { water.reduce(0) { $0 + $1.ml } }

    enum CodingKeys: String, CodingKey { case water, mindfulSeconds, sessions }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = try c.decodeIfPresent([WaterEntry].self, forKey: .water) ?? []
        mindfulSeconds = try c.decodeIfPresent(Int.self, forKey: .mindfulSeconds) ?? 0
        sessions = try c.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
    }
}

public struct WellbeingSettings: Codable, Equatable, Sendable {
    public var waterGoalML = 2000
    public var reminderMinutes = 90
    public var remindersEnabled = true
    /// Reminders stay quiet from `quietStartHour` until `quietEndHour` (wraps past midnight).
    public var quietStartHour = 21
    public var quietEndHour = 9
    public var patternID = BreathPattern.box.id
    public var sessionMinutes = 3
    /// nil follows the Mac's region (fl oz in the US).
    public var unit: VolumeUnit?
    public init() {}

    enum CodingKeys: String, CodingKey {
        case waterGoalML, reminderMinutes, remindersEnabled, quietStartHour, quietEndHour, patternID, sessionMinutes, unit
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WellbeingSettings()
        waterGoalML = try c.decodeIfPresent(Int.self, forKey: .waterGoalML) ?? d.waterGoalML
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? d.reminderMinutes
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? d.remindersEnabled
        quietStartHour = try c.decodeIfPresent(Int.self, forKey: .quietStartHour) ?? d.quietStartHour
        quietEndHour = try c.decodeIfPresent(Int.self, forKey: .quietEndHour) ?? d.quietEndHour
        patternID = try c.decodeIfPresent(String.self, forKey: .patternID) ?? d.patternID
        sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? d.sessionMinutes
        unit = try c.decodeIfPresent(VolumeUnit.self, forKey: .unit)
    }
}

public struct WellbeingData: Codable, Equatable, Sendable {
    public var days: [String: DayLog] = [:]
    public var settings = WellbeingSettings()
    public init() {}

    enum CodingKeys: String, CodingKey { case days, settings }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = try c.decodeIfPresent([String: DayLog].self, forKey: .days) ?? [:]
        settings = try c.decodeIfPresent(WellbeingSettings.self, forKey: .settings) ?? WellbeingSettings()
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func day(for date: Date, calendar: Calendar = .current) -> DayLog {
        days[Self.key(for: date, calendar: calendar)] ?? DayLog()
    }

    public var pattern: BreathPattern { BreathPattern.named(settings.patternID) }

    // MARK: Water

    public mutating func addWater(_ ml: Int, at date: Date, calendar: Calendar = .current) {
        guard ml > 0 else { return }
        days[Self.key(for: date, calendar: calendar), default: DayLog()].water.append(WaterEntry(time: date, ml: ml))
    }

    /// Removes and returns the most recent drink logged that day.
    @discardableResult
    public mutating func undoLastWater(on date: Date, calendar: Calendar = .current) -> Int? {
        let key = Self.key(for: date, calendar: calendar)
        guard var log = days[key], let last = log.water.popLast() else { return nil }
        days[key] = log
        return last.ml
    }

    /// Clears the water logged on one day (the daily reset). Mindfulness minutes are kept.
    public mutating func resetWater(on date: Date, calendar: Calendar = .current) {
        let key = Self.key(for: date, calendar: calendar)
        days[key]?.water = []
    }

    public func lastDrink(on date: Date, calendar: Calendar = .current) -> Date? {
        day(for: date, calendar: calendar).water.map(\.time).max()
    }

    public func goalMet(on date: Date, calendar: Calendar = .current) -> Bool {
        day(for: date, calendar: calendar).waterML >= settings.waterGoalML
    }

    /// Consecutive days that reached the goal. Today counts once it is met; until then
    /// the streak runs up to yesterday, so it doesn't read zero first thing in the morning.
    public func streak(now: Date, calendar: Calendar = .current) -> Int {
        var day = goalMet(on: now, calendar: calendar) ? now : (calendar.date(byAdding: .day, value: -1, to: now) ?? now)
        var count = 0
        while goalMet(on: day, calendar: calendar) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    /// The last seven days, oldest first.
    public func week(now: Date, calendar: Calendar = .current) -> [(date: Date, ml: Int)] {
        (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map { ($0, day(for: $0, calendar: calendar).waterML) }
        }
    }

    // MARK: Mindfulness

    public mutating func addMindful(seconds: Int, at date: Date, calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        let key = Self.key(for: date, calendar: calendar)
        days[key, default: DayLog()].mindfulSeconds += seconds
        days[key, default: DayLog()].sessions += 1
    }

    public mutating func prune(now: Date, keepDays: Int = 120, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepDays, to: now) else { return }
        let cutoffKey = Self.key(for: cutoff, calendar: calendar)
        days = days.filter { $0.key >= cutoffKey }
    }
}
