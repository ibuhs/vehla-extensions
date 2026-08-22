import Foundation

actor NumberCrunchWorker {
    static let shared = NumberCrunchWorker()

    func perform(_ action: NumberCrunchActionID, selectedText: String) throws -> String {
        switch action {
        case .sum:
            return try NumberCrunchEngine.sum(selectedText)
        case .average:
            return try NumberCrunchEngine.average(selectedText)
        case .evaluate:
            return try NumberCrunchEngine.evaluate(selectedText)
        case .toMetric:
            return try NumberCrunchEngine.convert(selectedText, to: .metric)
        case .toImperial:
            return try NumberCrunchEngine.convert(selectedText, to: .imperial)
        case .humanizeSize:
            return try NumberCrunchEngine.humanizeSizes(selectedText)
        case .toBytes:
            return try NumberCrunchEngine.toBytes(selectedText)
        case .toKilobytes:
            return try NumberCrunchEngine.toKilobytes(selectedText)
        case .toMegabytes:
            return try NumberCrunchEngine.toMegabytes(selectedText)
        case .toGigabytes:
            return try NumberCrunchEngine.toGigabytes(selectedText)
        }
    }
}
