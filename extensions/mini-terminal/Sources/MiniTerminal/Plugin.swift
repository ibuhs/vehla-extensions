import AppKit
import SwiftUI
import VehlaNotchSDK

@objc(MiniTerminalPlugin)
public final class MiniTerminalPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    @MainActor private let model = TerminalModel()

    @MainActor
    public func notchDidStart(_ host: any VehlaNotchHost) { model.start(VehlaNotch(host)) }

    @MainActor
    public func notchWillStop() { model.stop() }

    @MainActor
    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "terminal" else { return nil }
        model.ensureSession()
        return NSHostingController(rootView: TerminalTabView(model: model))
    }

    @MainActor
    public func tab(_ tabID: String, isVisible: Bool) { model.tabVisibilityChanged(isVisible) }

    @MainActor
    public func activity(_ activityID: String, performAction actionID: String) {
        model.activityAction(activityID, actionID)
    }
}
