import AppKit
import SwiftUI
import VehlaDockWidgetSDK

@objc(PeripheralMatrixPlugin)
public final class PeripheralMatrixPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [VehlaDockWidgetDescriptor(id: "peripheral-matrix", title: "Peripheral Matrix",
        subtitle: "Device batteries, live QMK layers, and keymap programming.",
        systemImage: "keyboard", preferredPopupWidth: 440, preferredPopupHeight: 400,
        supportedSurfaces: [.compact, .inline, .popup])]
    @MainActor private let model = PeripheralMatrixModel()
    @MainActor public func makeViewController(widgetID: String, surface: VehlaDockWidgetSurface,
        context: VehlaDockWidgetContext) throws -> NSViewController {
        guard widgetID == "peripheral-matrix" else { throw CocoaError(.fileNoSuchFile) }
        model.configure(context)
        return PeripheralMatrixSurfaceController(surface: surface, model: model)
    }
    @MainActor public func widget(_ widgetID: String, didEnter phase: VehlaDockWidgetVisibilityPhase) {
        phase == .hidden ? model.hide() : model.start()
    }
    @MainActor public func widget(_ widgetID: String, themeDidChange theme: VehlaDockWidgetTheme) { model.theme = theme }
    @MainActor public func widgetWillClose(_ widgetID: String) { model.close() }
}
