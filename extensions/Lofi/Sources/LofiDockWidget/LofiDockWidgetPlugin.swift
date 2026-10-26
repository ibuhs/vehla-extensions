import AppKit
import VehlaDockWidgetSDK

@objc(LofiDockWidgetPlugin)
public final class LofiDockWidgetPlugin: NSObject, VehlaDockWidgetPlugin {
    public let apiVersion = VehlaDockWidgetAPIVersion
    public let widgets = [VehlaDockWidgetDescriptor(id: "lofi", title: "Lofi", subtitle: "Music from your chosen folder",
        systemImage: "music.note", preferredPopupWidth: 420, preferredPopupHeight: 720,
        supportedSurfaces: [.compact, .inline, .popup])]
    @MainActor private var player: LofiPlayer?
    @MainActor public func makeViewController(widgetID: String, surface: VehlaDockWidgetSurface, context: VehlaDockWidgetContext) throws -> NSViewController {
        guard widgetID == "lofi" else { throw CocoaError(.fileNoSuchFile) }
        let player = self.player ?? LofiPlayer(directory: context.dataDirectory, context: context)
        self.player = player; player.theme = context.theme
        return LofiSurfaceController(surface: surface, model: player)
    }
    @MainActor public func widget(_ widgetID: String, didEnter phase: VehlaDockWidgetVisibilityPhase) { player?.setVisibility(phase) }
    @MainActor public func widget(_ widgetID: String, themeDidChange theme: VehlaDockWidgetTheme) { player?.theme = theme }
    @MainActor public func widgetWillClose(_ widgetID: String) { player?.shutdown(); player = nil }
}
