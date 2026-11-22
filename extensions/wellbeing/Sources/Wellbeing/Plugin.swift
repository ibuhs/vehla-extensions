import AppKit
import SwiftUI
import VehlaNotchSDK

@objc(WellbeingPlugin)
public final class WellbeingPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = WellbeingModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) { model.start(VehlaNotch(host)) }

    @MainActor
    public func notchWillStop() { model.stop() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "wellbeing" else { return nil }
        return NSHostingController(rootView: WellbeingTabView(model: model))
    }

    @MainActor
    public func activity(_ activityID: String, performAction actionID: String) {
        model.activityAction(activityID, actionID)
    }
}
