import AppKit
import SwiftUI
import VehlaDockWidgetSDK

@objc(QuickNoteDockWidgetPlugin)
public final class QuickNoteDockWidgetPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [
        VehlaDockWidgetDescriptor(
            id: "quicknote",
            title: "QuickNote",
            subtitle: "A scratchpad for the present moment",
            systemImage: "note.text",
            preferredPopupWidth: 760,
            preferredPopupHeight: 680,
            supportedSurfaces: [.compact, .inline, .popup]
        ),
    ]

    @MainActor private let model = QuickNoteModel()

    @MainActor
    public func makeViewController(
        widgetID: String,
        surface: VehlaDockWidgetSurface,
        context: VehlaDockWidgetContext
    ) throws -> NSViewController {
        guard widgetID == "quicknote" else {
            throw CocoaError(.fileNoSuchFile)
        }
        model.configure(context)
        return QuickNoteSurfaceController(surface: surface, model: model)
    }

    @MainActor
    public func widget(
        _ widgetID: String,
        didEnter phase: VehlaDockWidgetVisibilityPhase
    ) {
        phase == .hidden ? model.stop() : model.start()
    }

    @MainActor
    public func widget(
        _ widgetID: String,
        themeDidChange theme: VehlaDockWidgetTheme
    ) {
        model.theme = theme
    }

    @MainActor
    public func widgetWillClose(_ widgetID: String) {
        model.close()
    }
}

/// The host owns the surface's size. A plain AppKit container keeps SwiftUI's
/// transient fitting size (including the editor's zero intrinsic height) from
/// collapsing the view while Vehla embeds it in its popup.
@MainActor
final class QuickNoteSurfaceController: NSViewController {
    private let hosting: TransparentHostingView<QuickNoteRootView>
    private let initialSize: NSSize

    init(surface: VehlaDockWidgetSurface, model: QuickNoteModel) {
        hosting = TransparentHostingView(rootView: QuickNoteRootView(surface: surface, model: model))
        initialSize = switch surface {
        case .popup: NSSize(width: 760, height: 680)
        case .inline: NSSize(width: 240, height: 48)
        default: NSSize(width: 48, height: 48)
        }
        super.init(nibName: nil, bundle: nil)
        hosting.sizingOptions = []
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: initialSize))
        view.autoresizingMask = [.width, .height]
        let content = hosting
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// Keep the native hosting layer transparent as well as the SwiftUI content.
/// The host supplies the popup material and can embed this view in an opaque
/// parent; the widget must never paint the window background over that material.
@MainActor
final class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
