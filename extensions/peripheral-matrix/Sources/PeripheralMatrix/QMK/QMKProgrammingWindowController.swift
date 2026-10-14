import AppKit
import SwiftUI

/// Keep a single programming window per widget, independent of the dock popup.
@MainActor
final class QMKProgrammingWindowController: NSWindowController, NSWindowDelegate {
    private let model: PeripheralMatrixModel
    var onClose: (() -> Void)?
    init(model: PeripheralMatrixModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "QMK Keyboard Programming"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 740, height: 620)
        window.appearance = NSAppearance(named: model.theme?.isDark == true ? .darkAqua : .aqua)
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        let hosting = ProgrammingHostingView(rootView: QMKProgrammingView(model: model))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor, constant: 28),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        window.contentView = material
        window.center()
        super.init(window: window)
        window.delegate = self
    }
    required init?(coder: NSCoder) { nil }
    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Finish a bounded keyboard transaction before allowing the window to close.
        !model.editor.busy
    }
    func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor private final class ProgrammingHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
