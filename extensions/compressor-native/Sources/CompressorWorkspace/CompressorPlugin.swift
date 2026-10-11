import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(CompressorPlugin)
public final class CompressorPlugin: NSObject, VehlaNativeWorkspacePlugin {
    private static let workspaceID = "compressor"

    @MainActor private var themes: [String: ThemeBox] = [:]
    @MainActor private var controllers: [String: NSViewController] = [:]

    public override required init() { super.init() }

    public var apiVersion: Int { VehlaNativeUIAPIVersion }

    public var workspaces: [VehlaWorkspaceDescriptor] {
        [
            VehlaWorkspaceDescriptor(
                id: Self.workspaceID,
                title: "Compressor",
                subtitle: "Smaller files, same quality",
                systemImage: "arrow.down.right.and.arrow.up.left",
                // Vehla's own header bar needs about 760 pt to lay out without clipping.
                preferredWidth: 800,
                preferredHeight: 760,
                minimumWidth: 780,
                minimumHeight: 520,
                // File pickers take key focus, so the window must stay open.
                dismissBehavior: .persistent
            ),
        ]
    }

    @MainActor
    public func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController {
        guard workspaceID == Self.workspaceID else {
            throw NSError(
                domain: "com.ahmadjerow.compressor-glass",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown Compressor workspace “\(workspaceID)”."]
            )
        }
        let theme = ThemeBox(theme: context.theme)
        themes[workspaceID] = theme
        let model = CompressorModel(context: context)
        let controller = NSHostingController(
            rootView: CompressorWorkspaceView(model: model, themeBox: theme)
        )
        controller.sizingOptions = [] // Vehla owns the window size, not the content
        controller.view.appearance = Self.appearance(for: context.theme)
        controllers[workspaceID] = controller
        return controller
    }

    @MainActor
    public func workspace(_ workspaceID: String, themeDidChange theme: VehlaWorkspaceTheme) {
        themes[workspaceID]?.update(theme)
        controllers[workspaceID]?.view.appearance = Self.appearance(for: theme)
    }

    @MainActor
    public func workspaceWillClose(_ workspaceID: String) {
        themes[workspaceID] = nil
        controllers[workspaceID] = nil
    }

    private static func appearance(for theme: VehlaWorkspaceTheme) -> NSAppearance? {
        NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}
