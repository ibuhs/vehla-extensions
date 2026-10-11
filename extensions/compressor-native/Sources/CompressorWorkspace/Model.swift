import AppKit
import SwiftUI
import VehlaNativeUISDK

struct FileItem: Identifiable {
    enum State {
        case pending
        case working(Double)
        case done(CompressionResult)
    }

    let id = UUID()
    let url: URL
    let isDirectory: Bool
    let size: Int64
    let kind: MediaKind
    var state: State = .pending

    var name: String { url.lastPathComponent }
}

@MainActor
final class ThemeBox: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme
    init(theme: VehlaWorkspaceTheme) { self.theme = theme }
    func update(_ theme: VehlaWorkspaceTheme) { self.theme = theme }
}

@MainActor
final class CompressorModel: ObservableObject {
    enum Phase { case idle, running, finished }

    @Published private(set) var items: [FileItem] = []
    @Published private(set) var destination: URL?
    @Published var openWhenDone = true
    /// Indigo-tinted style when true; plain system Liquid Glass when false.
    @Published private(set) var tinted = false
    @Published private(set) var quality: QualityPreset = .balanced
    /// A problem to show above the footer, such as not enough free space.
    @Published private(set) var notice: String?
    /// Required tools that aren't installed, so the window can say so up front.
    @Published private(set) var missingRequired: [Dependency] = []
    @Published private(set) var missingOptional: [Dependency] = []
    @Published private(set) var homebrewAvailable = true
    @Published private(set) var hideOptionalHint = false
    @Published private(set) var phase: Phase = .idle

    private let context: VehlaWorkspaceContext
    private let toolFinder: (String) -> String?
    private var task: Task<Void, Never>?
    /// Held while a batch runs so the Mac doesn't idle-sleep mid-compression.
    private var keepAwake: NSObjectProtocol?

    init(context: VehlaWorkspaceContext, toolFinder: @escaping (String) -> String? = { Tools.find($0) }) {
        self.context = context
        self.toolFinder = toolFinder
        let saved = Self.loadSettings(from: context.dataDirectory)
        destination = saved.destination
        tinted = saved.tinted
        quality = saved.quality
        hideOptionalHint = saved.hideOptionalHint
        refreshDependencies()
    }

    // MARK: Tools

    func refreshDependencies() {
        missingRequired = Dependencies.missing(optional: false, finder: toolFinder)
        missingOptional = Dependencies.missing(optional: true, finder: toolFinder)
        homebrewAvailable = Dependencies.homebrewInstalled(finder: toolFinder)
    }

    func copyInstallCommand(_ dependencies: [Dependency]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Dependencies.installCommand(dependencies), forType: .string)
    }

    func openHomebrewSite() {
        NSWorkspace.shared.open(Dependencies.homebrewURL)
    }

    func dismissOptionalHint() {
        hideOptionalHint = true
        saveSettings()
    }

    // MARK: Derived

    var canStart: Bool {
        phase != .running && destination != nil && items.contains { if case .pending = $0.state { true } else { false } }
    }

    var results: [CompressionResult] {
        items.compactMap { if case .done(let r) = $0.state { r } else { nil } }
    }

    var totalSaved: Int64 { results.reduce(0) { $0 + $1.savedBytes } }

    // MARK: Picking

    func addFiles(_ urls: [URL]) {
        guard phase != .running else { return }
        notice = nil
        if phase == .finished { items.removeAll(); phase = .idle }
        for url in urls where !items.contains(where: { $0.url == url }) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            items.append(FileItem(
                url: url,
                isDirectory: isDir.boolValue,
                size: CompressionEngine.size(of: url),
                kind: MediaKind.classify(url, isDirectory: isDir.boolValue)
            ))
        }
    }

    func remove(_ id: FileItem.ID) {
        guard phase != .running else { return }
        notice = nil
        items.removeAll { $0.id == id }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Choose files to compress"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose the destination folder"
        panel.message = "Compressed files and copies of the originals are saved here."
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if let current = destination { panel.directoryURL = current }
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            notice = nil
            saveSettings()
        }
    }

    func setQuality(_ value: QualityPreset) {
        quality = value
        notice = nil
        saveSettings()
    }

    func setTinted(_ value: Bool) {
        tinted = value
        saveSettings()
    }

    func toggleTint() { setTinted(!tinted) }

    func openDestination() {
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
    }

    func newBatch() {
        guard phase != .running else { return }
        items.removeAll()
        phase = .idle
    }

    // MARK: Running

    func start() {
        guard canStart, let destination else { return }
        let writable = FileManager.default.isWritableFile(atPath: destination.path)
        guard writable else {
            context.showMessage("Vehla can't write to that folder. Choose another destination.")
            return
        }

        let work = items.filter { if case .pending = $0.state { true } else { false } }
        if let problem = Preflight.check(sizes: work.map(\.size), destination: destination) {
            notice = problem
            return
        }

        notice = nil
        phase = .running
        keepAwake = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Compressing files"
        )
        let preset = quality
        task = Task { [weak self] in
            let engine = CompressionEngine(destination: destination, quality: preset)
            for entry in work {
                if Task.isCancelled { break }
                self?.setState(entry.id, .working(0))
                let id = entry.id
                let result = await engine.compress(entry.url, isDirectory: entry.isDirectory) { value in
                    Task { @MainActor in self?.setState(id, .working(value)) }
                }
                self?.setState(id, .done(result))
            }
            self?.finish()
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func setState(_ id: FileItem.ID, _ state: FileItem.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }

    private func finish() {
        if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake) }
        keepAwake = nil
        // Anything cancelled before it started goes back to pending.
        phase = .finished
        let done = results
        let compressed = done.filter { $0.status == .compressed }.count
        context.notify(
            title: "Compressor finished",
            body: compressed > 0
                ? "Saved \(Format.bytes(totalSaved)) across \(compressed) file\(compressed == 1 ? "" : "s")."
                : "Nothing could be made smaller without losing quality."
        )
        if openWhenDone, done.contains(where: { $0.status != .failed }) { openDestination() }
    }

    // MARK: Remembered settings

    private static func stateURL(_ directory: URL) -> URL {
        directory.appendingPathComponent("state.json")
    }

    static func loadSettings(from directory: URL) -> (destination: URL?, tinted: Bool, quality: QualityPreset, hideOptionalHint: Bool) {
        guard let data = try? Data(contentsOf: stateURL(directory)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false, .balanced, false)
        }
        var destination: URL?
        if let path = object["destination"] as? String {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                destination = URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        let quality = (object["quality"] as? String).flatMap(QualityPreset.init(rawValue:)) ?? .balanced
        return (destination, object["tinted"] as? Bool ?? false, quality, object["hideOptionalHint"] as? Bool ?? false)
    }

    private func saveSettings() {
        let directory = context.dataDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var object: [String: Any] = ["tinted": tinted, "quality": quality.rawValue, "hideOptionalHint": hideOptionalHint]
        if let destination { object["destination"] = destination.path }
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            try? data.write(to: Self.stateURL(directory), options: .atomic)
        }
    }
}
