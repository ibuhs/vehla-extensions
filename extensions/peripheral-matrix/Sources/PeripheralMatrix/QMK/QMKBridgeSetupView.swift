import AppKit
import SwiftUI

struct QMKBridgeSetupContent {
    static func text(_ name: String, extension ext: String) -> String? {
        let host = Bundle(for: PeripheralMatrixPlugin.self)
        let packaged = host.url(forResource: "PeripheralMatrix_PeripheralMatrix", withExtension: "bundle").flatMap { Bundle(url: $0) }
        #if DEBUG
        let resources = packaged ?? Bundle.module
        #else
        guard let resources = packaged else { return nil }
        #endif
        guard let url = resources.url(forResource: name, withExtension: ext) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    static let guide = text("bridge-setup-guide", extension: "md")
    static let prompt = text("bridge-setup-ai-prompt", extension: "txt")
}

struct QMKBridgeSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Set up live layer control", systemImage: "keyboard.badge.ellipsis").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let guide = QMKBridgeSetupContent.guide {
                        ForEach(Array(guide.components(separatedBy: "\n\n").flatMap { $0.hasPrefix("1. ") ? $0.components(separatedBy: "\n") : [$0] }.enumerated()), id: \.offset) { index, paragraph in
                            if index > 0 {
                                Text(paragraph.replacingOccurrences(of: "## ", with: ""))
                                    .font(paragraph.hasPrefix("## ") ? .headline : .body)
                                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                            }
                        }
                    } else { Text("Setup guide is missing. Reinstall the widget package.").foregroundStyle(.orange) }
                    if let prompt = QMKBridgeSetupContent.prompt {
                        DisclosureGroup("Preview the AI setup prompt") {
                            Text(prompt).font(.caption).textSelection(.enabled).padding(.top, 8)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(copied ? "Copied. Paste into your AI assistant." : "Private keymaps and macros are not included.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy AI setup prompt", systemImage: "doc.on.doc") {
                    guard let prompt = QMKBridgeSetupContent.prompt else { return }
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(prompt, forType: .string)
                }.disabled(QMKBridgeSetupContent.prompt == nil)
                    .accessibilityIdentifier("qmk.bridge.copy-ai-prompt")
            }
        }.padding(24).frame(width: 620, height: 680)
    }
}
