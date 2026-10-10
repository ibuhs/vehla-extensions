import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(CoverArtSearchWorkspacePlugin)
public final class CoverArtSearchWorkspacePlugin: NSObject, VehlaNativeWorkspacePlugin {
    @MainActor private var themes: [String: ThemeCoordinator] = [:]
    @MainActor private var stores: [String: CoverArtSearchStore] = [:]
    @MainActor private var controllers: [String: NSViewController] = [:]

    public override required init() {
        super.init()
    }

    public var apiVersion: Int { VehlaNativeUIAPIVersion }

    public var workspaces: [VehlaWorkspaceDescriptor] {
        [
            VehlaWorkspaceDescriptor(
                id: "cover-art-search",
                title: "Cover Art Search",
                subtitle: "IMDb posters and artwork",
                systemImage: "photo.on.rectangle.angled",
                preferredWidth: 760,
                preferredHeight: 610,
                minimumWidth: 600,
                minimumHeight: 480,
                dismissBehavior: .dismissOnResignKey
            ),
        ]
    }

    @MainActor
    public func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController {
        guard workspaceID == "cover-art-search" else {
            throw NSError(
                domain: "com.kailalabs.vehla.cover-art-search",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown workspace \(workspaceID)."]
            )
        }

        let theme = ThemeCoordinator(context.theme)
        let store = CoverArtSearchStore(context: context)
        let controller = NSHostingController(
            rootView: CoverArtSearchView(store: store, theme: theme)
        )
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        controller.view.appearance = Self.appearance(for: context.theme)

        themes[workspaceID] = theme
        stores[workspaceID] = store
        controllers[workspaceID] = controller
        return controller
    }

    @MainActor
    public func workspace(
        _ workspaceID: String,
        themeDidChange theme: VehlaWorkspaceTheme
    ) {
        themes[workspaceID]?.update(theme)
        controllers[workspaceID]?.view.appearance = Self.appearance(for: theme)
    }

    @MainActor
    public func workspaceWillClose(_ workspaceID: String) {
        themes[workspaceID] = nil
        stores[workspaceID] = nil
        controllers[workspaceID] = nil
    }

    private static func appearance(for theme: VehlaWorkspaceTheme) -> NSAppearance? {
        NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

@MainActor
final class ThemeCoordinator: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme

    init(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }

    func update(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }
}
