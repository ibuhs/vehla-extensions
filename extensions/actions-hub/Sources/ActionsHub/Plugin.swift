import AppKit
import SwiftUI
import VehlaNotchSDK

@objc(ActionsHubPlugin)
public final class ActionsHubPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = ActionsModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) { model.start(VehlaNotch(host)) }

    @MainActor
    public func notchWillStop() { model.stop() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "actions" else { return nil }
        return NSHostingController(rootView: ActionsTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) { model.tabVisible(isVisible) }

    @MainActor
    public func activity(_ activityID: String, performAction actionID: String) {
        model.activityAction(activityID, actionID)
    }
}
