import AppKit
import SwiftUI
import VehlaDockWidgetSDK

/// Vehla owns the surface size. SwiftUI's ScrollView has a transient zero
/// fitting size, so embed it in a stable AppKit view instead of exposing a
/// bare NSHostingController to the Dock host.
@MainActor
final class VolumeMatrixSurfaceController: NSViewController {
    private let hosting: VolumeHostingView<VolumeMatrixView>
    private let initialSize: NSSize

    init(surface: VehlaDockWidgetSurface, model: VolumeMatrixModel) {
        hosting = VolumeHostingView(rootView: VolumeMatrixView(surface: surface, model: model))
        switch surface {
        case .popup: initialSize = NSSize(width: 560, height: 660)
        case .inline: initialSize = NSSize(width: 240, height: 48)
        default: initialSize = NSSize(width: 48, height: 48)
        }
        super.init(nibName: nil, bundle: nil)
        hosting.sizingOptions = []
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: initialSize))
        view.autoresizingMask = [.width, .height]
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

/// Keep Vehla's popup material visible behind the widget content.
@MainActor
private final class VolumeHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
