import AppKit
import SwiftUI
import VehlaNotchSDK

@objc(AgentApprovalsPlugin)
public final class AgentApprovalsPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = ApprovalsModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) { model.start(VehlaNotch(host)) }

    @MainActor
    public func notchWillStop() { model.stop() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "agents" else { return nil }
        return NSHostingController(rootView: AgentsTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) { model.tabVisibilityChanged(isVisible) }

    @MainActor
    public func activity(_ activityID: String, performAction actionID: String) {
        model.activityAction(activityID, actionID)
    }
}
