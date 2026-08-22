import Foundation

actor DataExtractorWorker {
    static let shared = DataExtractorWorker()

    func perform(_ action: DataExtractorActionID, selectedText: String) throws -> String {
        switch action {
        case .emails:
            return try DataExtractorEngine.emails(selectedText)
        case .phones:
            return try DataExtractorEngine.phones(selectedText)
        case .ips:
            return try DataExtractorEngine.ips(selectedText)
        case .mentions:
            return try DataExtractorEngine.mentions(selectedText)
        case .hashtags:
            return try DataExtractorEngine.hashtags(selectedText)
        case .all:
            return try DataExtractorEngine.all(selectedText)
        case .csv:
            return try DataExtractorEngine.csv(selectedText)
        }
    }
}
