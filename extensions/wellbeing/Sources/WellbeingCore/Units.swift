import Foundation

/// How water is shown and entered. Everything is stored in millilitres.
public enum VolumeUnit: String, Codable, Sendable, CaseIterable {
    case milliliters, ounces

    public static let mlPerOunce = 29.5735

    /// US locales default to fluid ounces, everyone else to millilitres.
    public static func automatic(locale: Locale = .current) -> VolumeUnit {
        locale.measurementSystem == .us ? .ounces : .milliliters
    }

    public var label: String { self == .ounces ? "fl oz" : "ml" }

    /// Quick-add buttons, in this unit.
    public var quickAmounts: [Int] { self == .ounces ? [8, 16, 32] : [150, 250, 500] }
    /// One glass, in this unit (used by the reminder's quick-log button).
    public var glass: Int { self == .ounces ? 8 : 250 }
    public var goalStep: Int { self == .ounces ? 8 : 250 }
    public var defaultGoalML: Int { self == .ounces ? toML(64) : 2000 }

    public func toML(_ amount: Int) -> Int {
        self == .ounces ? Int((Double(amount) * Self.mlPerOunce).rounded()) : amount
    }

    public func fromML(_ ml: Int) -> Int {
        self == .ounces ? Int((Double(ml) / Self.mlPerOunce).rounded()) : ml
    }

    public func format(ml: Int) -> String { "\(fromML(ml)) \(label)" }
}
