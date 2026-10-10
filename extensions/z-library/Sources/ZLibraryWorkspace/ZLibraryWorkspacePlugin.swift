import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(ZLibraryWorkspacePlugin)
public final class ZLibraryWorkspacePlugin: NSObject, VehlaNativeWorkspacePlugin {
    @MainActor private var themes: [String: ZLibraryThemeCoordinator] = [:]
    @MainActor private var stores: [String: ZLibraryStore] = [:]
    @MainActor private var controllers: [String: NSViewController] = [:]

    public override required init() {
        super.init()
    }

    public var apiVersion: Int { VehlaNativeUIAPIVersion }

    public var workspaces: [VehlaWorkspaceDescriptor] {
        [
            VehlaWorkspaceDescriptor(
                id: "z-library",
                title: "Z-Library",
                subtitle: "Search books and manage downloads",
                systemImage: "books.vertical",
                preferredWidth: 780,
                preferredHeight: 620,
                minimumWidth: 620,
                minimumHeight: 480,
                dismissBehavior: .persistent
            ),
        ]
    }

    @MainActor
    public func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController {
        guard workspaceID == "z-library" else {
            throw NSError(
                domain: "com.kailalabs.vehla.z-library",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown workspace \(workspaceID)."]
            )
        }

        let theme = ZLibraryThemeCoordinator(context.theme)
        let store = ZLibraryStore(context: context)
        let controller = NSHostingController(
            rootView: ZLibraryView(store: store, theme: theme)
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
final class ZLibraryThemeCoordinator: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme

    init(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }

    func update(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }
}
