import AppKit
import SwiftUI
import VehlaNativeUISDK

@objc(ToolboxWorkspacePlugin)
public final class ToolboxWorkspacePlugin: NSObject, VehlaNativeWorkspacePlugin {
    @MainActor private var themes: [String: ThemeCoordinator] = [:]
    @MainActor private var controllers: [String: NSViewController] = [:]

    public override required init() { super.init() }

    public var apiVersion: Int { VehlaNativeUIAPIVersion }

    public var workspaces: [VehlaWorkspaceDescriptor] {
        [
            VehlaWorkspaceDescriptor(
                id: "toolbox",
                title: "Toolbox",
                subtitle: "JSON, encoding, crypto, date, and text tools",
                systemImage: "wrench.and.screwdriver",
                preferredWidth: 1_400,
                preferredHeight: 860,
                minimumWidth: 920,
                minimumHeight: 620,
                dismissBehavior: .persistent
            ),
        ]
    }

    @MainActor
    public var quickGlassActions: [VehlaWorkspaceQuickGlassActionDescriptor] {
        QuickGlassActionCatalog.all.map(\.descriptor)
    }

    @MainActor
    public func performQuickGlassAction(
        _ actionID: String,
        request: VehlaWorkspaceQuickGlassRequest,
        context: VehlaWorkspaceContext,
        completion: VehlaWorkspaceQuickGlassCompletion
    ) {
        guard let action = QuickGlassActionCatalog.action(id: actionID) else {
            completion.quickGlassActionDidFinish(
                VehlaWorkspaceQuickGlassResult(
                    errorMessage: "Unknown Toolbox action “\(actionID)”."
                )
            )
            return
        }

        let toolRequest: ToolRequest
        do {
            toolRequest = try action.request(selectedText: request.selectedText)
        } catch {
            completion.quickGlassActionDidFinish(
                VehlaWorkspaceQuickGlassResult(
                    errorMessage: error.localizedDescription,
                    delivery: action.delivery
                )
            )
            return
        }

        let worker = ToolWorker(dataDirectory: context.dataDirectory)
        Task { @MainActor in
            do {
                let output = try await worker.execute(toolRequest)
                completion.quickGlassActionDidFinish(
                    VehlaWorkspaceQuickGlassResult(
                        outputText: output.text,
                        delivery: action.delivery
                    )
                )
            } catch {
                completion.quickGlassActionDidFinish(
                    VehlaWorkspaceQuickGlassResult(
                        errorMessage: error.localizedDescription,
                        delivery: action.delivery
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
        guard workspaceID == "toolbox" else {
            throw NSError(
                domain: "com.ibuhs.vehla.toolbox",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Unknown Toolbox workspace “\(workspaceID)”.",
                ]
            )
        }
        let coordinator = ThemeCoordinator(context.theme)
        themes[workspaceID] = coordinator
        let controller = NSHostingController(
            rootView: ToolboxWorkspaceView(context: context, theme: coordinator)
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
