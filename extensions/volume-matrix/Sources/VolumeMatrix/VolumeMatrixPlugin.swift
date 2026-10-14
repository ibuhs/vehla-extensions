import AppKit
import VehlaDockWidgetSDK

@objc(VolumeMatrixPlugin)
public final class VolumeMatrixPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [VehlaDockWidgetDescriptor(id: "volume-matrix", title: "Volume Matrix",
        subtitle: "Disk space, live activity, and mount/eject controls.", systemImage: "externaldrive.fill",
        preferredPopupWidth: 560, preferredPopupHeight: 660, supportedSurfaces: [.compact, .inline, .popup])]
    @MainActor private let model = VolumeMatrixModel()
    @MainActor public func makeViewController(widgetID: String, surface: VehlaDockWidgetSurface, context: VehlaDockWidgetContext) throws -> NSViewController {
        guard widgetID == "volume-matrix" else { throw CocoaError(.fileNoSuchFile) }
        model.theme = context.theme
        return VolumeMatrixSurfaceController(surface: surface, model: model)
    }
    @MainActor public func widget(_ widgetID: String, didEnter phase: VehlaDockWidgetVisibilityPhase) {
        phase == .hidden ? model.hide() : model.start()
    }
    @MainActor public func widget(_ widgetID: String, themeDidChange theme: VehlaDockWidgetTheme) { model.theme = theme }
    @MainActor public func widgetWillClose(_ widgetID: String) { model.hide() }
}
