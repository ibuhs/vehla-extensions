import AppKit
import SwiftUI

@MainActor
final class PreviewState: ObservableObject {
    @Published var wallpaper: Wallpaper?
    @Published var image: NSImage?
    @Published var isLoadingFull = true
}

/// A borderless panel that can take the keyboard without activating the app, so Space / Esc / arrows work.
final class PreviewPanel: NSPanel {
    var onClose: (() -> Void)?
    var onNavigate: ((Int) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 53, 36: onClose?()            // space, escape, return
        case 123, 126: onNavigate?(-1)          // left, up
        case 124, 125: onNavigate?(1)           // right, down
        default: super.keyDown(with: event)
        }
    }
}

/// The large preview shown outside the Notch, in the style of Quick Look: Space opens and closes it.
@MainActor
final class PreviewController {
    static let shared = PreviewController()

    private let state = PreviewState()
    private var panel: PreviewPanel?
    private var loadTask: Task<Void, Never>?
    private var closeToken = 0
    private weak var model: WallhavenModel?
    private var maxPixel = 2048

    var isShowing: Bool { panel?.isVisible == true && panel?.alphaValue ?? 0 > 0.01 }

    func show(_ wallpaper: Wallpaper, model: WallhavenModel) {
        self.model = model
        closeToken += 1
        let panel = self.panel ?? makePanel()
        self.panel = panel
        apply(wallpaper, to: panel, animate: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }
        load(wallpaper)
    }

    /// Moves an already open preview to another wallpaper.
    func update(_ wallpaper: Wallpaper, model: WallhavenModel) {
        guard isShowing, let panel else { return }
        self.model = model
        apply(wallpaper, to: panel, animate: true)
        load(wallpaper)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        loadTask?.cancel()
        closeToken += 1
        let token = closeToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            MainActor.assumeIsolated {
                // Not if it was shown again in the meantime.
                if let self, self.closeToken == token { self.tearDown(panel) }
            }
        }
    }

    /// Frees the images and the window's own full-screen buffer. Clearing the state isn't enough: a window that
    /// is off screen doesn't redraw, so its layers would go on holding the last image.
    private func tearDown(_ panel: PreviewPanel) {
        panel.onClose = nil
        panel.onNavigate = nil
        panel.contentView = nil
        panel.close()
        self.panel = nil
        state.image = nil
        state.wallpaper = nil
        model?.releaseFullImages()
    }

    // MARK: Building

    private func makePanel() -> PreviewPanel {
        let panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.onClose = { [weak self] in self?.close() }
        panel.onNavigate = { [weak self] offset in self?.model?.selectNeighbor(offset) }
        panel.contentView = NSHostingView(rootView: PreviewContent(state: state, close: { [weak self] in self?.close() }))
        return panel
    }

    private func apply(_ wallpaper: Wallpaper, to panel: PreviewPanel, animate: Bool) {
        state.wallpaper = wallpaper
        state.image = ThumbnailCache.shared.image(for: wallpaper.thumbs.original)
            ?? ThumbnailCache.shared.image(for: wallpaper.thumbs.large)
        state.isLoadingFull = true

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        let size = PreviewLayout.size(forResolution: wallpaper.resolution,
                                      in: CGSize(width: area.width * 0.82, height: area.height * 0.82))
        let frame = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        maxPixel = Int((max(size.width, size.height) * screen.backingScaleFactor).rounded(.up))
        panel.setFrame(frame, display: true, animate: animate)
    }

    private func load(_ wallpaper: Wallpaper) {
        loadTask?.cancel()
        guard let model else { return }
        let maxPixel = maxPixel
        loadTask = Task { [state] in
            if state.image == nil, let thumb = await model.loadThumbnail(wallpaper.thumbs.original), state.wallpaper?.id == wallpaper.id {
                state.image = thumb
            }
            let full = await model.loadFullImage(wallpaper, maxPixel: maxPixel)
            guard !Task.isCancelled, state.wallpaper?.id == wallpaper.id else { return }
            if let full { state.image = full }
            state.isLoadingFull = false
        }
    }
}

/// Hands the image straight to the window server. SwiftUI's `Image` redraws it through CoreGraphics, which keeps
/// its own full-size copy of each one long after it was shown.
private struct LayerImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.contentsGravity = .resizeAspect
        view.layer?.actions = ["contents": NSNull()]
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) { view.layer?.contents = nil }
}

private struct PreviewContent: View {
    @ObservedObject var state: PreviewState
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black
            if let image = state.image {
                LayerImage(image: image)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.isLoadingFull && state.image != nil {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading full size…").font(.system(size: 11, weight: .medium))
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(12)
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                if let wallpaper = state.wallpaper {
                    Text(wallpaper.resolution).font(.system(size: 12, weight: .semibold).monospacedDigit())
                    if let size = wallpaper.fileSize {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer()
                Text("Space or Esc to close  ·  ← → to browse").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.top, 26).padding(.bottom, 10)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: close)
        .environment(\.colorScheme, .dark)
    }
}
