import AppKit
import Testing
@testable import QuickNoteDockWidget

struct MathReferenceTests {
    @Test func referenceCoversEveryBuiltinAndHasWorkingExamples() async throws {
        let entries = MathReferenceCatalog.entries
        #expect(Set(entries.flatMap(\.names)) == MathParser.builtins)
        #expect(Set(entries.map(\.id)).count == entries.count)
        let tools = ScratchTools()
        for entry in entries where entry.category != "Limits" {
            let result = try await tools.analyze(entry.example)
            #expect(!result.mathResults.isEmpty, "Missing result for \(entry.syntax)")
            #expect(!result.mathResults.contains { $0.answer == "Check expression" }, "Invalid example: \(entry.example)")
        }
        #expect(entries.contains { $0.matches("SIN") })
        #expect(entries.contains { $0.matches("monthly") })
    }

    @Test @MainActor func referenceIsNonmodalReusableAndCleanedUp() {
        _ = NSApplication.shared
        let model = QuickNoteModel()
        model.mathReference.show(model: model)
        let first = model.mathReference.panel
        #expect(first != nil)
        #expect(first?.hidesOnDeactivate == false)
        #expect(first?.styleMask.contains(.nonactivatingPanel) == true)
        model.mathReference.show(model: model)
        #expect(model.mathReference.panel === first)
        model.stop()
        #expect(model.mathReference.panel === first)
        first?.close()
        model.mathReference.show(model: model)
        #expect(model.mathReference.panel === first)
        model.close()
        #expect(model.mathReference.panel == nil)
        #expect(first?.contentView == nil)
    }
}
