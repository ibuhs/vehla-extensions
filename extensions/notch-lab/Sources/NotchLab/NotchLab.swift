import AppKit
import SwiftUI
import VehlaNotchSDK

/// The bundle's principal class. Vehla creates it when the Lab tab is first opened (the manifest has no
/// "background"), and calls `notchWillStop` when the Notch stops or the extension is turned off.
@objc(NotchLabPlugin)
public final class NotchLabPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    private var model: LabModel?

    public func notchDidStart(_ host: any VehlaNotchHost) {
        model = LabModel(notch: VehlaNotch(host))
    }

    public func notchWillStop() {
        model?.stop()
        model = nil
    }

    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "lab", let model else { return nil }
        let controller = NSHostingController(rootView: LabView(model: model))
        controller.sizingOptions = []
        return controller
    }

    public func activity(_ activityID: String, performAction actionID: String) {
        model?.pressed(activityID, actionID)
    }
}

@MainActor
@Observable
final class LabModel {
    let notch: VehlaNotch
    var lastEvent = "Nothing pressed yet"
    private var progressTask: Task<Void, Never>?

    init(notch: VehlaNotch) { self.notch = notch }

    func message() {
        lastEvent = "Message started: close the Notch to see it (6 seconds)"
        notch.show(.init(id: "message", systemImage: "hand.wave.fill", title: "Hello from Notch Lab", detail: "Gone in 6 seconds",
                         tintHex: "#FFD60A", duration: 6))
    }

    func countdown() {
        lastEvent = "Countdown started: close the Notch to see it (30 seconds)"
        notch.show(.init(id: "countdown", systemImage: "timer", title: "Countdown", tintHex: "#FF9F0A",
                         timerEnd: Date().addingTimeInterval(30), duration: 30,
                         buttons: [.init(id: "copy", title: "Copy"), .init(id: "stop", title: "Stop", systemImage: "xmark")]))
    }

    /// Updates one activity in place ten times, then ends it.
    func progress() {
        lastEvent = "Progress started: close the Notch to see it (6 seconds)"
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            for step in 0...10 {
                guard let self, !Task.isCancelled else { return }
                self.notch.show(.init(id: "progress", systemImage: "arrow.down", title: "Downloading", detail: "\(step * 10)%",
                                      tintHex: "#30D158", progress: Double(step) / 10))
                try? await Task.sleep(for: .seconds(0.6))
            }
            self?.notch.end("progress")
        }
    }

    func endAll() {
        lastEvent = "Ended every activity"
        progressTask?.cancel()
        ["message", "countdown", "progress"].forEach(notch.end)
    }

    func pressed(_ activityID: String, _ actionID: String) {
        lastEvent = actionID.isEmpty ? "Clicked \(activityID)" : "Pressed \(actionID) on \(activityID)"
        switch actionID {
        case "copy": lastEvent += notch.copy("Copied from Notch Lab") ? " (copied)" : " (copy refused)"
        case "stop": notch.end(activityID)
        case "": notch.openTab("lab")
        default: break
        }
    }

    func stop() {
        progressTask?.cancel()
    }
}

struct LabView: View {
    let model: LabModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Close the Notch after pressing a button to see its live activity.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                button("Message", "hand.wave.fill", model.message)
                button("Countdown", "timer", model.countdown)
                button("Progress", "arrow.down", model.progress)
                button("End All", "xmark", model.endAll)
            }
            Text(model.lastEvent)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func button(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
