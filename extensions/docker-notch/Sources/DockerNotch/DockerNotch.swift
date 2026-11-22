import AppKit
import SwiftUI
import VehlaNotchSDK

/// The bundle's principal class. The manifest says "background", so Vehla starts it with the Notch: it has to
/// be running to notice a container stopping.
@objc(DockerNotchPlugin)
public final class DockerNotchPlugin: NSObject, VehlaNotchPlugin {
    public let apiVersion = VehlaNotchAPIVersion
    private var model: DockerModel?

    public func notchDidStart(_ host: any VehlaNotchHost) {
        let model = DockerModel(notch: VehlaNotch(host))
        self.model = model
        model.start()
    }

    public func notchWillStop() {
        model?.stop()
        model = nil
    }

    public func makeTabViewController(_ tabID: String) -> NSViewController? {
        guard tabID == "containers", let model else { return nil }
        let controller = NSHostingController(rootView: DockerView(model: model))
        controller.sizingOptions = []
        return controller
    }

    public func tab(_ tabID: String, isVisible: Bool) {
        if isVisible { model?.tabAppeared() }
    }

    public func activity(_ activityID: String, performAction actionID: String) {
        model?.pressed(activityID, actionID)
    }
}

@MainActor
@Observable
final class DockerModel {
    enum State: Equatable {
        case loading
        /// The `docker` command wasn't found.
        case notInstalled
        /// Installed, but Docker isn't running.
        case notRunning
        case ready
    }

    let notch: VehlaNotch
    private(set) var containers: [DockerContainer] = []
    private(set) var state = State.loading
    /// Containers with a start, stop or restart of ours in progress.
    private(set) var busy: Set<String> = []
    var alerts: DockerAlerts {
        didSet {
            guard alerts != oldValue else { return }
            try? alerts.rawValue.write(to: settingsURL, atomically: true, encoding: .utf8)
            if alerts == .off { ["stopped", "unhealthy"].forEach(notch.end) }
            watch()
        }
    }

    private let events = DockerEventStream()
    private var refreshTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    /// Containers this extension stopped itself, so its own Stop isn't announced.
    private var expectedStops: [String: Date] = [:]
    /// The container each activity is about, for its Restart button.
    private var announced: [String: DockerContainer] = [:]
    private var isStopped = false

    private var settingsURL: URL { notch.dataDirectory.appendingPathComponent("alerts.txt") }

    init(notch: VehlaNotch) {
        self.notch = notch
        let saved = (try? String(contentsOf: notch.dataDirectory.appendingPathComponent("alerts.txt"), encoding: .utf8)) ?? ""
        alerts = DockerAlerts(rawValue: saved.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .all
    }

    func start() {
        refresh()
        watch()
    }

    func stop() {
        isStopped = true
        events.stop()
        refreshTask?.cancel()
        retryTask?.cancel()
    }

    func tabAppeared() {
        refresh()
        watch()
    }

    // MARK: Reading

    /// Reads the list once. Several calls in a row fold into one read a moment later.
    func refresh() {
        guard !isStopped else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let output = await DockerCLI.run(["ps", "-a", "--no-trunc=false", "--format", "{{json .}}"])
            guard let self, !Task.isCancelled else { return }
            guard let output else {
                self.state = .notInstalled
                self.containers = []
                return
            }
            if output.status == 0 {
                self.containers = DockerParser.containers(output.text)
                self.state = .ready
            } else {
                self.containers = []
                self.state = .notRunning
            }
        }
    }

    /// Keeps one `docker events` process while alerts are on. When Docker isn't running it looks again every
    /// two minutes with one sleeping task; nothing else repeats.
    private func watch() {
        guard !isStopped else { return }
        if alerts == .off {
            events.stop()
            retryTask?.cancel()
            return
        }
        guard !events.isRunning else { return }
        let started = events.start(
            onEvent: { [weak self] event in Task { @MainActor in self?.handle(event) } },
            onEnd: { [weak self] in Task { @MainActor in self?.streamEnded() } })
        if !started { retryLater() }
    }

    private func streamEnded() {
        guard !isStopped else { return }
        refresh()
        retryLater()
    }

    private func retryLater() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled else { return }
            self?.watch()
            self?.refresh()
        }
    }

    private func handle(_ event: DockerEvent) {
        guard !isStopped else { return }
        refresh()
        let container = containers.first { $0.id.hasPrefix(event.id) || event.id.hasPrefix($0.id) }
            ?? DockerContainer(id: event.id, name: event.name, image: "", state: "", status: "")
        switch event.kind {
        case .died(let exitCode):
            let now = Date()
            expectedStops = expectedStops.filter { now.timeIntervalSince($0.value) < 30 }
            if expectedStops.removeValue(forKey: container.id) != nil { return }
            guard alerts.announces(exitCode: exitCode) else { return }
            announced["stopped"] = container
            notch.show(.init(id: "stopped", systemImage: exitCode == 0 ? "stop.circle.fill" : "exclamationmark.triangle.fill",
                             title: event.name, detail: exitCode == 0 ? "Stopped" : "Exited with code \(exitCode)",
                             tintHex: exitCode == 0 ? "#8E8E93" : "#FF453A", duration: 12,
                             buttons: [.init(id: "restart", title: "Restart")]))
        case .unhealthy:
            guard alerts != .off else { return }
            announced["unhealthy"] = container
            notch.show(.init(id: "unhealthy", systemImage: "heart.slash.fill", title: event.name, detail: "Unhealthy",
                             tintHex: "#FF9F0A", duration: 12, buttons: [.init(id: "restart", title: "Restart")]))
        case .started:
            // It is back: what was said about it no longer holds.
            for (activity, shown) in announced where shown.id == container.id {
                notch.end(activity)
                announced[activity] = nil
            }
        case .changed:
            break
        }
    }

    // MARK: Acting

    enum Action: String { case start, stop, restart }

    func perform(_ action: Action, on container: DockerContainer) {
        guard !busy.contains(container.id), !isStopped else { return }
        busy.insert(container.id)
        if action != .start { expectedStops[container.id] = Date() }
        Task { [weak self] in
            _ = await DockerCLI.run([action.rawValue, container.id], timeout: 60)
            self?.busy.remove(container.id)
            self?.refresh()
        }
    }

    func pressed(_ activityID: String, _ actionID: String) {
        switch actionID {
        case "restart":
            if let container = announced[activityID] { perform(.start, on: container) }
            notch.end(activityID)
        default:
            notch.openTab("containers")
        }
    }
}

struct DockerView: View {
    let model: DockerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer(minLength: 8)
                Button { model.alerts = model.alerts.next } label: {
                    Label("Alerts: \(model.alerts.title)", systemImage: model.alerts == .off ? "bell.slash.fill" : "bell.fill")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .help("When a stopped container shows in the closed Notch. Click to change.")
                icon("arrow.clockwise", "Refresh") { model.refresh() }
            }
            content
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var title: String {
        switch model.state {
        case .ready: DockerParser.summary(model.containers)
        case .loading: "Docker"
        case .notInstalled: "Docker isn't installed"
        case .notRunning: "Docker isn't running"
        }
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            note("Reading your containers…")
        case .notInstalled:
            note("The docker command wasn't found. Install Docker Desktop, OrbStack or Colima, then press Refresh.")
        case .notRunning:
            note("Start Docker, then press Refresh. This tab looks again by itself every two minutes.")
        case .ready where model.containers.isEmpty:
            note("Containers you create appear here.")
        case .ready:
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.containers) { container in row(container) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func row(_ container: DockerContainer) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(container.isRunning ? Color.green : .white.opacity(0.25))
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(container.image.isEmpty ? container.status : "\(container.image) · \(container.status)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if model.busy.contains(container.id) {
                ProgressView().controlSize(.small).frame(width: 24, height: 24)
            } else if container.isRunning {
                icon("arrow.clockwise", "Restart") { model.perform(.restart, on: container) }
                icon("stop.fill", "Stop") { model.perform(.stop, on: container) }
            } else {
                icon("play.fill", "Start") { model.perform(.start, on: container) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func icon(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
