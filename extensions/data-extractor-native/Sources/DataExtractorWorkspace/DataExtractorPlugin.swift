import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(DataExtractorPlugin)
public final class DataExtractorPlugin: NSObject, VehlaNativeWorkspacePlugin {
    @MainActor private var themes: [String: ThemeBox] = [:]
    @MainActor private var controllers: [String: NSViewController] = [:]

    public override required init() { super.init() }

    public var apiVersion: Int { VehlaNativeUIAPIVersion }

    public var workspaces: [VehlaWorkspaceDescriptor] {
        [
            VehlaWorkspaceDescriptor(
                id: "data-extractor",
                title: "Data Extractor",
                subtitle: "QuickGlass extraction tools",
                systemImage: "text.magnifyingglass",
                preferredWidth: 720,
                preferredHeight: 600,
                minimumWidth: 560,
                minimumHeight: 420,
                dismissBehavior: .dismissOnResignKey
            ),
        ]
    }

    @MainActor
    public var quickGlassActions: [VehlaWorkspaceQuickGlassActionDescriptor] {
        DataExtractorActionCatalog.all.map(\.descriptor)
    }

    @MainActor
    public func performQuickGlassAction(
        _ actionID: String,
        request: VehlaWorkspaceQuickGlassRequest,
        context: VehlaWorkspaceContext,
        completion: VehlaWorkspaceQuickGlassCompletion
    ) {
        guard let action = DataExtractorActionCatalog.action(id: actionID) else {
            completion.quickGlassActionDidFinish(
                VehlaWorkspaceQuickGlassResult(
                    errorMessage: DataExtractorError.unknownAction(actionID).localizedDescription
                )
            )
            return
        }

        let selectedText = request.selectedText
        let delivery = action.delivery
        Task { @MainActor in
            do {
                let output = try await DataExtractorWorker.shared.perform(
                    action,
                    selectedText: selectedText
                )
                completion.quickGlassActionDidFinish(
                    VehlaWorkspaceQuickGlassResult(
                        outputText: output,
                        delivery: delivery
                    )
                )
            } catch {
                completion.quickGlassActionDidFinish(
                    VehlaWorkspaceQuickGlassResult(
                        errorMessage: error.localizedDescription,
                        delivery: delivery
                    )
                )
            }
        }
    }

    @MainActor
    public func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController {
        guard workspaceID == "data-extractor" else {
            throw NSError(
                domain: "com.ibuhs.vehla.data-extractor",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unknown Data Extractor workspace “\(workspaceID)”.",
                ]
            )
        }
        let theme = ThemeBox(theme: context.theme)
        themes[workspaceID] = theme
        let controller = NSHostingController(
            rootView: DataExtractorWorkspaceView(theme: theme)
        )
        controller.view.appearance = Self.appearance(for: context.theme)
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
        controllers[workspaceID] = nil
    }

    private static func appearance(for theme: VehlaWorkspaceTheme) -> NSAppearance? {
        NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }
}

@MainActor
final class ThemeBox: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme

    init(theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }

    func update(_ theme: VehlaWorkspaceTheme) {
        self.theme = theme
    }
}
