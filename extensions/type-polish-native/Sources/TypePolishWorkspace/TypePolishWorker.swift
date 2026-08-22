import Foundation

actor TypePolishWorker {
    static let shared = TypePolishWorker()

    func perform(_ action: TypePolishActionID, selectedText: String) throws -> String {
        switch action {
        case .straightenQuotes:
            return try TypePolishEngine.straightenQuotes(selectedText)
        case .cleanDashes:
            return try TypePolishEngine.cleanDashes(selectedText)
        case .unwrap:
            return try TypePolishEngine.unwrap(selectedText)
        case .collapseSpaces:
            return try TypePolishEngine.collapseSpaces(selectedText)
        case .stripJunk:
            return try TypePolishEngine.stripJunk(selectedText)
        case .polish:
            return try TypePolishEngine.polish(selectedText)
        }
    }
}
