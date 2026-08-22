import Foundation

actor ListWorker {
    static let shared = ListWorker()

    func perform(
        _ action: ListLabActionID,
        selectedText: String,
        clipboardText: String = ""
    ) throws -> String {
        switch action {
        case .splitComma:
            return try ListEngine.split(selectedText, separator: ",")
        case .joinComma:
            return try ListEngine.join(selectedText, separator: ", ")
        case .splitPipe:
            return try ListEngine.split(selectedText, separator: "|")
        case .joinPipe:
            return try ListEngine.join(selectedText, separator: " | ")
        case .shuffle:
            return try ListEngine.shuffle(selectedText)
        case .number:
            return try ListEngine.number(selectedText)
        case .quote:
            return try ListEngine.quote(selectedText)
        case .wrapParens:
            return try ListEngine.wrapParens(selectedText)
        case .unwrap:
            return try ListEngine.unwrap(selectedText)
        case .prefixClipboard:
            return try ListEngine.prefix(selectedText, with: clipboardText)
        }
    }
}
