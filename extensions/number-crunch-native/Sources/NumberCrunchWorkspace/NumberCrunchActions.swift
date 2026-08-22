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
    case toKilobytes = "num.to-kb"
    case toMegabytes = "num.to-mb"
    case toGigabytes = "num.to-gb"

    var title: String {
        switch self {
        case .sum: "Sum Numbers"
        case .average: "Average"
        case .evaluate: "Evaluate"
        case .toMetric: "To Metric"
        case .toImperial: "To Imperial"
        case .humanizeSize: "Humanize Size"
        case .toBytes: "To Bytes"
        case .toKilobytes: "To KB"
        case .toMegabytes: "To MB"
        case .toGigabytes: "To GB"
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
        case .toKilobytes: "arrow.up.right"
        case .toMegabytes: "arrow.up.forward"
        case .toGigabytes: "arrow.up.circle"
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
        case .toKilobytes: "Converts any file size to kilobytes."
        case .toMegabytes: "Converts any file size to megabytes."
        case .toGigabytes: "Converts any file size to gigabytes."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery {
        switch self {
        case .sum, .average, .evaluate: .compactResult
        case .toMetric, .toImperial, .humanizeSize, .toBytes,
             .toKilobytes, .toMegabytes, .toGigabytes: .replaceSelection
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
