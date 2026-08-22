import Foundation
import VehlaNativeUISDK

enum NumberCrunchActionID: String, CaseIterable, Sendable {
    case sum = "num.sum"
    case average = "num.average"
    case evaluate = "num.evaluate"
    case toMetric = "num.to-metric"
    case toImperial = "num.to-imperial"
    case humanizeSize = "num.humanize-size"
    case toBytes = "num.to-bytes"

    var title: String {
        switch self {
        case .sum: "Sum Numbers"
        case .average: "Average"
        case .evaluate: "Evaluate"
        case .toMetric: "To Metric"
        case .toImperial: "To Imperial"
        case .humanizeSize: "Humanize Size"
        case .toBytes: "To Bytes"
        }
    }

    var systemImage: String {
        switch self {
        case .sum: "plus"
        case .average: "divide"
        case .evaluate: "function"
        case .toMetric: "ruler"
        case .toImperial: "ruler.fill"
        case .humanizeSize: "internaldrive"
        case .toBytes: "doc"
        }
    }

    var caption: String {
        switch self {
        case .sum: "Adds every number in the selection."
        case .average: "Averages every number in the selection."
        case .evaluate: "Evaluates +, -, *, /, ^, and parentheses."
        case .toMetric: "Converts pounds, miles, feet, inches, and °F."
        case .toImperial: "Converts kilograms, kilometers, meters, and °C."
        case .humanizeSize: "Turns bytes into KiB, MiB, GiB, and so on."
        case .toBytes: "Turns KB, MB, GiB, and bits into bytes."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery {
        switch self {
        case .sum, .average, .evaluate: .compactResult
        case .toMetric, .toImperial, .humanizeSize, .toBytes: .replaceSelection
        }
    }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum NumberCrunchActionCatalog {
    static let all: [NumberCrunchActionID] = NumberCrunchActionID.allCases

    static func action(id: String) -> NumberCrunchActionID? {
        NumberCrunchActionID(rawValue: id)
    }
}
