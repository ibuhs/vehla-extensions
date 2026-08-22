import Foundation

actor MarkdownWorker {
    static let shared = MarkdownWorker()

    func perform(_ action: MarkdownQuickActionID, selectedText: String) throws -> String {
        switch action {
        case .normalize:
            return try MarkdownEngine.normalize(selectedText)
        case .strip:
            return try MarkdownEngine.strip(selectedText)
        case .formatTables:
            return try MarkdownEngine.formatTables(selectedText)
        case .unwrapLinks:
            return try MarkdownEngine.unwrapLinks(selectedText)
        case .extractLinks:
            return try MarkdownEngine.renderLinks(selectedText)
        case .extractHeadings:
            return try MarkdownEngine.renderHeadings(selectedText)
        }
    }
}
