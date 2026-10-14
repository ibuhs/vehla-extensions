import AppKit
import SwiftUI
import VehlaDockWidgetSDK

/// Vehla owns the surface size. SwiftUI's ScrollView has a transient zero
/// fitting size, so embed it in a stable AppKit view instead of exposing a
/// bare NSHostingController to the Dock host.
@MainActor
final class PeripheralMatrixSurfaceController: NSViewController {
    private let hosting: MatrixHostingView<PeripheralMatrixView>
    private let initialSize: NSSize

    init(surface: VehlaDockWidgetSurface, model: PeripheralMatrixModel) {
        hosting = MatrixHostingView(rootView: PeripheralMatrixView(surface: surface, model: model))
        switch surface {
        case .popup: initialSize = NSSize(width: 440, height: 340)
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
private final class MatrixHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
