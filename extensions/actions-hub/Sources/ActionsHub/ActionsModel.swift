import ActionsHubCore
import AppKit
import NotchKit
import SwiftUI
import VehlaNotchSDK

struct SceneProgress: Equatable {
    let id: String
    let completed: Int
    let total: Int
}

@MainActor
final class ActionsModel: ObservableObject {
    @Published private(set) var config = ActionsConfig.default
    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var toggleStates: [ToggleID: Bool] = [:]
    @Published private(set) var busyToggles: Set<ToggleID> = []
    @Published private(set) var scene: SceneProgress?
    @Published private(set) var runningShortcut: String?
    @Published private(set) var status: String?

    private let controls = SystemControls()
    private var notch: VehlaNotch?
    private var store: NKJSONStore<ActionsConfig>?
    private var refreshTask: Task<Void, Never>?
    private var sceneTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var caffeinate: Process?
    private var awakeSince: Date?

    var configURL: URL? { store?.url }

    // MARK: Lifecycle

    func start(_ notch: VehlaNotch) {
        self.notch = notch
        let store = NKJSONStore<ActionsConfig>(directory: notch.dataDirectory, name: "actions.json")
        self.store = store
        if let saved = store.load() {
            config = saved
        } else {
            store.save(config) // write the defaults so there is a file to edit
        }
    }

    func stop() {
        refreshTask?.cancel()
        sceneTask?.cancel()
        statusTask?.cancel()
        stopCaffeinate()
        notch?.end("scene")
        notch = nil
    }

    func reloadConfig() {
        if let saved = store?.load() { config = saved }
    }

    /// Reloads the config and the current toggle states whenever the tab comes on screen.
    func tabVisible(_ visible: Bool) {
        refreshTask?.cancel()
        guard visible else { return }
        reloadConfig()
        refreshTask = Task { [weak self] in
            await self?.refreshToggles()
            if self?.shortcuts.isEmpty == true { await self?.refreshShortcuts() }
        }
    }

    func refreshShortcuts() async {
        shortcuts = await controls.listShortcuts()
    }

    func refreshToggles() async {
        for toggle in config.toggles {
            toggleStates[toggle] = toggle == .keepAwake ? (caffeinate?.isRunning ?? false) : await controls.isOn(toggle)
        }
    }

    // MARK: Toggles

    func flip(_ toggle: ToggleID) {
        let target = !(toggleStates[toggle] ?? false)
        Task { await set(toggle, on: target) }
    }

    func set(_ toggle: ToggleID, on: Bool) async {
        busyToggles.insert(toggle)
        defer { busyToggles.remove(toggle) }
        if toggle == .keepAwake {
            on ? startCaffeinate() : stopCaffeinate()
            toggleStates[.keepAwake] = caffeinate?.isRunning ?? false
            return
        }
        do {
            try await controls.set(toggle, on: on)
            toggleStates[toggle] = await controls.isOn(toggle)
        } catch {
            flash("\(toggle.title) failed")
        }
    }

    private func startCaffeinate() {
        guard caffeinate?.isRunning != true else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-d", "-i"]
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.caffeinateEnded() }
        }
        do { try process.run() } catch { flash("Couldn't keep the Mac awake"); return }
        caffeinate = process
        awakeSince = Date()
        notch?.show(VehlaNotchActivity(
            id: "awake", systemImage: "cup.and.saucer.fill", title: "Keeping awake", tintHex: NK.Hex.warning,
            timerStart: awakeSince, buttons: [VehlaNotchActivityButton(id: "stop", title: "Stop", systemImage: "stop.fill")]))
    }

    private func stopCaffeinate() {
        caffeinate?.terminationHandler = nil
        if caffeinate?.isRunning == true { caffeinate?.terminate() }
        caffeinate = nil
        awakeSince = nil
        notch?.end("awake")
    }

    private func caffeinateEnded() {
        guard caffeinate?.isRunning != true else { return }
        caffeinate = nil
        awakeSince = nil
        toggleStates[.keepAwake] = false
        notch?.end("awake")
    }

    func activityAction(_ activityID: String, _ actionID: String) {
        if activityID == "awake" {
            if actionID == "stop" { Task { await set(.keepAwake, on: false) } } else { notch?.openTab("actions") }
        } else if activityID == "scene" {
            notch?.openTab("actions")
        }
    }

    // MARK: Shortcuts, apps, scenes

    func runShortcut(_ name: String) {
        guard runningShortcut == nil else { return }
        runningShortcut = name
        Task {
            defer { runningShortcut = nil }
            do { try await controls.runShortcut(name); flash("Ran \(name)") }
            catch { flash("\(name) failed") }
        }
    }

    func open(app: AppEntry) {
        Task {
            do { try await controls.open(app: app.name) } catch { flash("Couldn't open \(app.name)") }
        }
    }

    func run(_ scene: ActionScene) {
        guard self.scene == nil else { return }
        self.scene = SceneProgress(id: scene.id, completed: 0, total: scene.steps.count)
        let executor = LiveExecutor(controls: controls) { [weak self] toggle, on in
            await self?.set(toggle, on: on)
        }
        sceneTask = Task { [weak self] in
            let failures = await SceneRunner.run(scene, executor: executor) { done, total in
                Task { @MainActor in self?.sceneProgressed(scene, done, total) }
            }
            self?.sceneFinished(scene, failures: failures)
        }
    }

    private func sceneProgressed(_ scene: ActionScene, _ done: Int, _ total: Int) {
        guard self.scene?.id == scene.id else { return }
        self.scene = SceneProgress(id: scene.id, completed: done, total: total)
        notch?.show(VehlaNotchActivity(
            id: "scene", systemImage: scene.icon, title: scene.name, detail: "\(done) of \(total)",
            progress: total == 0 ? 1 : Double(done) / Double(total), duration: 120))
    }

    private func sceneFinished(_ scene: ActionScene, failures: [StepFailure]) {
        self.scene = nil
        let ok = failures.isEmpty
        notch?.show(VehlaNotchActivity(
            id: "scene", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
            title: ok ? "\(scene.name) is on" : scene.name,
            detail: ok ? nil : "\(failures.count) step\(failures.count == 1 ? "" : "s") failed",
            tintHex: ok ? NK.Hex.success : NK.Hex.warning, duration: 4))
        flash(ok ? "\(scene.name) done" : failures[0].message)
    }

    func revealConfig() {
        guard let url = configURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.status = nil }
        }
    }
}

struct LiveExecutor: ActionExecutor {
    let controls: SystemControls
    let toggle: @Sendable (ToggleID, Bool) async -> Void

    func run(_ step: Step) async throws {
        switch step {
        case .shortcut(let name): try await controls.runShortcut(name)
        case .app(let name): try await controls.open(app: name)
        case .url(let url): try await controls.open(url: url)
        case .toggle(let id, let on): await toggle(id, on)
        case .wait(let seconds): try await Task.sleep(for: .seconds(min(max(seconds, 0), 60)))
        }
    }
}
