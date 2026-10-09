import AppKit
import SwiftUI

/// One reusable, nonmodal reference panel per plugin instance. Hiding a dock
/// surface does not dismiss it; unloading the plugin explicitly releases it.
@MainActor
final class MathReferenceWindow {
    private(set) var panel: NSPanel?

    func show(model: QuickNoteModel) {
        if let panel { panel.orderFront(nil); return }
        let panel = QuickNotePanel.make(title: "QuickNote — Math Reference", size: NSSize(width: 480, height: 640),
                                        minSize: NSSize(width: 380, height: 340), content: MathReferenceView(model: model))
        // No focus is taken from the editor's text view just to open the guide.
        QuickNotePanel.placeBesideKeyWindow(panel)
        self.panel = panel
        updateAppearance(isDark: model.theme?.isDark)
        panel.orderFront(nil)
    }

    func updateAppearance(isDark: Bool?) {
        panel?.appearance = QuickNotePanel.appearance(isDark: isDark)
    }

    func close() {
        panel?.close()
        panel?.contentView = nil
        panel = nil
    }
}

private struct MathReferenceView: View {
    @ObservedObject var model: QuickNoteModel
    @State private var query = ""
    private var primary: Color { Color(nsColor: model.editorTextColor) }
    private var secondary: Color { Color(nsColor: model.theme?.secondaryTextColor ?? .secondaryLabelColor) }
    private var entries: [MathReferenceEntry] { MathReferenceCatalog.entries.filter { $0.matches(query.trimmingCharacters(in: .whitespacesAndNewlines)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Math Reference", systemImage: "function").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Done") { model.mathReference.close() }
            }
            Text("Keep this window open while you type in your note. Select any example to copy it.")
                .font(.system(size: 11)).foregroundStyle(secondary)
            TextField("Search functions, syntax or examples", text: $query)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Search math reference")
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.category.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(secondary)
                            Text(entry.syntax).font(.system(size: 12, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                            Text(entry.detail).font(.system(size: 11)).foregroundStyle(secondary).fixedSize(horizontal: false, vertical: true)
                            Text(entry.example).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                            Divider()
                        }
                    }
                    if entries.isEmpty { Text("No matching functions. Try a name such as sin, pmt or mean.").font(.system(size: 12)).foregroundStyle(secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .foregroundStyle(primary).padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
