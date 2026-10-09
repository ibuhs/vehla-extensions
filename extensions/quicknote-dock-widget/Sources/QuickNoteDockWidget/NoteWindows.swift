import AppKit
import SwiftUI

/// Notes popped out of the dock popup into their own floating panels, one per
/// note. Like Math Reference they stay open while the dock surface is hidden;
/// unloading the plugin closes them. A note that leaves the library or moves
/// to The Void closes its panel.
@MainActor
final class NoteWindows: NSObject, NSWindowDelegate {
    private var panels: [String: NSPanel] = [:]
    private weak var model: QuickNoteModel?

    func contains(_ id: String) -> Bool { panels[id] != nil }

    func show(id: String, model: QuickNoteModel) {
        if let panel = panels[id] { panel.makeKeyAndOrderFront(nil); return }
        self.model = model
        let title = model.library.notes.first { $0.id == id }?.title ?? "Note"
        let panel = QuickNotePanel.make(title: title, size: NSSize(width: 420, height: 520),
                                        minSize: NSSize(width: 280, height: 220), content: PoppedNoteView(model: model, id: id))
        QuickNotePanel.placeBesideKeyWindow(panel, cascade: panels.count)
        panel.appearance = QuickNotePanel.appearance(isDark: model.theme?.isDark)
        panel.delegate = self
        panels[id] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func retitle(_ id: String, _ title: String) {
        if panels[id]?.title != title { panels[id]?.title = title }
    }

    func updateAppearance(isDark: Bool?) {
        let appearance = QuickNotePanel.appearance(isDark: isDark)
        for panel in panels.values { panel.appearance = appearance }
    }

    func close(_ id: String) { panels[id]?.close() }

    func closeAll() { for panel in Array(panels.values) { panel.close() } }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let id = panels.first(where: { $0.value === panel })?.key else { return }
        panels[id] = nil
        model?.poppedClosed(id)
    }
}

private struct PoppedNoteView: View {
    @ObservedObject var model: QuickNoteModel
    let id: String
    @State private var focusToken = UUID()
    private var note: ScratchNote? { model.library.notes.first { $0.id == id && $0.deleted == nil } }
    private var primary: Color { Color(nsColor: model.editorTextColor) }
    private var secondary: Color { Color(nsColor: model.theme?.secondaryTextColor ?? .secondaryLabelColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let note {
                let analysis = model.poppedAnalyses[id] ?? ScratchAnalysis()
                HStack {
                    Text(analysis.mode.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(2)
                    Spacer()
                    if let slot = note.slot {
                        Label("Slot \(slot)", systemImage: "pin.fill").font(.system(size: 10)).foregroundStyle(secondary)
                    }
                }.padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 8)
                InlineNoteEditor(text: note.content, textColor: model.editorTextColor, autoFocus: true,
                                 onEdit: { model.edit(id, text: $0) }, onSave: model.saveCurrent,
                                 fontSize: model.library.fontSize, focusToken: focusToken,
                                 analysis: analysis, resultColor: model.library.mathResultColor ?? .automatic,
                                 onResultCopy: model.didCopyResult,
                                 linedPaper: model.library.linedPaper,
                                 onCommand: { model.poppedCommand($0, id: id) },
                                 onShortcut: { model.poppedShortcut($0, id: id) },
                                 onImage: { model.recognizeImage($0, into: id) },
                                 onImageFile: { model.recognizeFile($0, into: id) },
                                 onOpenURL: { model.context?.open($0) })
                    .padding(.horizontal, 18).frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 12) {
                    Text(model.isDirty ? "Saving…" : "Saved on this Mac")
                    Spacer()
                    Text(analysis.summary)
                    Button { model.copyNote(id) } label: { Image(systemName: "doc.on.doc") }.help("Copy note")
                    Button { model.select(id) } label: { Image(systemName: "dock.rectangle") }.help("Select in QuickNote")
                }
                .buttonStyle(.borderless).font(.system(size: 10)).foregroundStyle(secondary)
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
        }
        .foregroundStyle(primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: note == nil, initial: true) { if $1 { model.noteWindows.close(id) } }
        .onChange(of: note?.title, initial: true) { if let title = $1 { model.noteWindows.retitle(id, title) } }
    }
}
