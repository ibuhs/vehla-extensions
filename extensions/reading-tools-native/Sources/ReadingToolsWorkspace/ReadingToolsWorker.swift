import Foundation

actor ReadingToolsWorker {
    static let shared = ReadingToolsWorker()

    func perform(_ action: ReadingToolsActionID, selectedText: String) throws -> String {
        try ReadingToolsEngine.output(for: action, text: selectedText)
    }
}
