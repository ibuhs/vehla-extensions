import AppKit
import SwiftUI
import VehlaDockWidgetSDK

@objc(HertzlyDockWidgetPlugin)
public final class HertzlyDockWidgetPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [
        VehlaDockWidgetDescriptor(
            id: "hertzly-radio",
            title: "Hertzly",
            subtitle: "Internet radio tuner",
            systemImage: "radio.fill",
            preferredPopupWidth: 560,
            preferredPopupHeight: 700,
            supportedSurfaces: [.compact, .inline, .popup]
        ),
    ]

    @MainActor private let model = HertzlyModel()

    @MainActor
    public func makeViewController(
        widgetID: String,
        surface: VehlaDockWidgetSurface,
        context: VehlaDockWidgetContext
    ) throws -> NSViewController {
        guard widgetID == "hertzly-radio" else {
            throw CocoaError(.fileNoSuchFile)
        }
        model.configure(context: context)
        return NSHostingController(rootView: HertzlyRootView(surface: surface, model: model))
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
        model.updateTheme(theme)
    }

    @MainActor
    public func widgetWillClose(_ widgetID: String) {
        model.close()
    }
}
