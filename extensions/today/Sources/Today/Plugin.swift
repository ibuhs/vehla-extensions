import AppKit
import SwiftUI
import VehlaNotchSDK

@objc(TodayPlugin)
public final class TodayPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = TodayModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) { model.start(VehlaNotch(host)) }

    @MainActor
    public func notchWillStop() { model.stop() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "today" else { return nil }
        return NSHostingController(rootView: TodayTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) {
        guard tabID == "today" else { return }
        model.tabVisibilityChanged(isVisible)
    }

    @MainActor
    public func activity(_ activityID: String, performAction actionID: String) {
        model.activityAction(activityID, actionID)
    }
}
