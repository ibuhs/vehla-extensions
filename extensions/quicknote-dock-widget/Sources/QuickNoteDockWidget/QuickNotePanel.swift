import AppKit
import SwiftUI

/// The frosted, nonactivating floating panels QuickNote opens beside its dock
/// popup (Math Reference and popped-out notes).
@MainActor
enum QuickNotePanel {
    static func make<Content: View>(title: String, size: NSSize, minSize: NSSize, content: Content) -> NSPanel {
        let panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
                                 backing: .buffered, defer: false)
        panel.title = title
        // The panel is clear, so the material must also run under the title
        // bar; otherwise the traffic-light strip shows whatever is behind it.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.minSize = minSize
        panel.isOpaque = false
        panel.backgroundColor = .clear
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        let host = TransparentHostingView(rootView: content)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            host.topAnchor.constraint(equalTo: material.safeAreaLayoutGuide.topAnchor),
            host.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        panel.contentView = material
        panel.center()
        return panel
    }

    /// Places the panel beside the key window (the dock popup) where the screen
    /// permits, stepping each further panel down by `cascade` title bars.
    static func placeBesideKeyWindow(_ panel: NSPanel, cascade: Int = 0) {
        guard let editor = NSApp.keyWindow, editor !== panel, let screen = editor.screen else { return }
        let bounds = screen.visibleFrame
        let right = editor.frame.maxX + 12
        let x = right + panel.frame.width <= bounds.maxX ? right : editor.frame.minX - panel.frame.width - 12
        let y = editor.frame.maxY - panel.frame.height - CGFloat(cascade % 8) * 28
        panel.setFrameOrigin(NSPoint(x: min(max(x, bounds.minX), bounds.maxX - panel.frame.width),
                                     y: min(max(y, bounds.minY), bounds.maxY - panel.frame.height)))
    }

    static func appearance(isDark: Bool?) -> NSAppearance? {
        isDark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
    }
}

@MainActor
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
