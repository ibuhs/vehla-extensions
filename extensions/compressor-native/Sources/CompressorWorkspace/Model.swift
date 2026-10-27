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
    let kind: MediaKind
    var size: Int64
    /// For folders: files that "Compress each file" would process, and the largest one.
    var fileCount = 1
    var largestFile: Int64 = 0
    var folderMode: FolderMode = .zip
    var state: State = .pending

    var name: String { url.lastPathComponent }
    var compressesContents: Bool { isDirectory && folderMode == .contents }

    var typeLabel: String {
        isDirectory ? "Folder · \(fileCount) file\(fileCount == 1 ? "" : "s")" : kind.label
    }

    var fraction: Double {
        switch state {
        case .pending: 0
        case .working(let value): value
        case .done: 1
        }
    }

    var isPending: Bool { if case .pending = state { true } else { false } }
}

@MainActor
final class ThemeBox: ObservableObject {
    @Published private(set) var theme: VehlaWorkspaceTheme
    init(theme: VehlaWorkspaceTheme) { self.theme = theme }
    func update(_ theme: VehlaWorkspaceTheme) { self.theme = theme }
}

/// Everything remembered between sessions.
struct Settings {
    var destination: URL?
    var tinted = false
    var quality: QualityPreset = .balanced
    var hideOptionalHint = false
    var fastVideo = false
    var trashOriginals = false
    var folderMode: FolderMode = .zip

    private static func url(_ directory: URL) -> URL { directory.appendingPathComponent("state.json") }

    static func load(from directory: URL) -> Settings {
        var settings = Settings()
        guard let data = try? Data(contentsOf: url(directory)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return settings }
        if let path = object["destination"] as? String {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                settings.destination = URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        settings.tinted = object["tinted"] as? Bool ?? false
        settings.quality = (object["quality"] as? String).flatMap(QualityPreset.init(rawValue:)) ?? .balanced
        settings.hideOptionalHint = object["hideOptionalHint"] as? Bool ?? false
        settings.fastVideo = object["fastVideo"] as? Bool ?? false
        settings.trashOriginals = object["trashOriginals"] as? Bool ?? false
        settings.folderMode = (object["folderMode"] as? String).flatMap(FolderMode.init(rawValue:)) ?? .zip
        return settings
    }

    func save(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var object: [String: Any] = [
            "tinted": tinted, "quality": quality.rawValue, "hideOptionalHint": hideOptionalHint,
            "fastVideo": fastVideo, "trashOriginals": trashOriginals, "folderMode": folderMode.rawValue,
        ]
        if let destination { object["destination"] = destination.path }
        if let data = try? JSONSerialization.data(withJSONObject: object) {
            try? data.write(to: Self.url(directory), options: .atomic)
        }
    }
}

@MainActor
final class CompressorModel: ObservableObject {
    enum Phase { case idle, running, finished }

    @Published private(set) var items: [FileItem] = []
    @Published var openWhenDone = true
    @Published private(set) var settings: Settings
    /// A problem to show above the footer, such as not enough free space.
    @Published private(set) var notice: String?
    /// Required tools that aren't installed, so the window can say so up front.
    @Published private(set) var missingRequired: [Dependency] = []
    @Published private(set) var missingOptional: [Dependency] = []
    @Published private(set) var homebrewAvailable = true
    @Published private(set) var phase: Phase = .idle

    var destination: URL? { settings.destination }
    var tinted: Bool { settings.tinted }
    var quality: QualityPreset { settings.quality }
    var hideOptionalHint: Bool { settings.hideOptionalHint }
    var fastVideo: Bool { settings.fastVideo }
    var trashOriginals: Bool { settings.trashOriginals }

    private let context: VehlaWorkspaceContext
    private let toolFinder: (String) -> String?
    private let confirmTrash: () -> Bool
    private let trashAction: @Sendable (URL) throws -> Void
    private var task: Task<Void, Never>?
    private var control = BatchControl()
    /// Held while a batch runs so the Mac doesn't idle-sleep mid-compression.
    private var keepAwake: NSObjectProtocol?

    // Bookkeeping for the running batch: which job belongs to which row.
    private var runIDs: [UUID] = []
    private var unitOwners: [UUID] = []
    private var unitSizes: [Int64] = []
    private var unitProgress: [Double] = []
    private var unitResults: [Int: CompressionResult] = [:]
    private var ownerUnits: [UUID: [Int]] = [:]

    init(
        context: VehlaWorkspaceContext,
        toolFinder: @escaping (String) -> String? = { Tools.find($0) },
        confirmTrash: @escaping () -> Bool = CompressorModel.askToConfirmTrash,
        trash: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.context = context
        self.toolFinder = toolFinder
        self.confirmTrash = confirmTrash
        self.trashAction = trash
        settings = Settings.load(from: context.dataDirectory)
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

    func dismissOptionalHint() { update { $0.hideOptionalHint = true } }

    // MARK: Derived

    var canStart: Bool {
        phase != .running && destination != nil && items.contains(where: \.isPending)
    }

    var results: [CompressionResult] {
        items.compactMap { if case .done(let r) = $0.state { r } else { nil } }
    }

    var totalSaved: Int64 { results.reduce(0) { $0 + $1.savedBytes } }

    private var runItems: [FileItem] { items.filter { runIDs.contains($0.id) } }

    /// The whole batch, weighted by size so a big video counts for more.
    var overallProgress: Double {
        let run = runItems
        let total = run.reduce(0.0) { $0 + Double(max($1.size, 1)) }
        guard total > 0 else { return 0 }
        return run.reduce(0.0) { $0 + Double(max($1.size, 1)) * $1.fraction } / total
    }

    var runCounts: (done: Int, total: Int) {
        let run = runItems
        return (run.filter { if case .done = $0.state { true } else { false } }.count, run.count)
    }

    // MARK: Picking

    func addFiles(_ urls: [URL]) {
        guard phase != .running else { return }
        notice = nil
        if phase == .finished { items.removeAll(); phase = .idle }
        for url in urls where !items.contains(where: { $0.url == url }) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let size = CompressionEngine.size(of: url)
            var item = FileItem(url: url, isDirectory: isDir.boolValue,
                                kind: MediaKind.classify(url, isDirectory: isDir.boolValue), size: size)
            item.largestFile = size
            if item.isDirectory {
                let stats = FolderExpansion.stats(of: url)
                item.fileCount = stats.files
                item.largestFile = stats.largest
                item.folderMode = settings.folderMode
            }
            items.append(item)
        }
    }

    /// Removes a row at any time. During a batch it also stops that row's
    /// work; files already saved in the destination are kept.
    func remove(_ id: FileItem.ID) {
        notice = nil
        if phase == .running, runIDs.contains(id) {
            control.stop(id)
            runIDs.removeAll { $0 == id }
        }
        items.removeAll { $0.id == id }
        if items.isEmpty, phase == .finished { phase = .idle }
    }

    func setFolderMode(_ id: FileItem.ID, _ mode: FolderMode) {
        guard phase != .running, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].folderMode = mode
        notice = nil
        update { $0.folderMode = mode } // new folders start with the last choice
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
            notice = nil
            update { $0.destination = url }
        }
    }

    func setQuality(_ value: QualityPreset) {
        notice = nil
        update { $0.quality = value }
    }

    func setTinted(_ value: Bool) { update { $0.tinted = value } }
    func toggleTint() { setTinted(!tinted) }
    func setFastVideo(_ value: Bool) { update { $0.fastVideo = value } }

    /// Turning this on asks first, because it moves files to the Trash.
    func setTrashOriginals(_ value: Bool) {
        if value, !trashOriginals, !confirmTrash() { return }
        update { $0.trashOriginals = value }
    }

    nonisolated static func askToConfirmTrash() -> Bool {
        MainActor.assumeIsolated {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Move originals to the Trash?"
            alert.informativeText = """
                After a file is compressed, Compressor checks that its copy in the destination folder \
                is identical, then moves the original to the Trash. You can restore it from the Trash \
                until you empty it. Originals are never touched if the destination is the same folder.
                """
            alert.addButton(withTitle: "Turn On")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }
    }

    func openDestination() {
        guard let destination else { return }
        NSWorkspace.shared.open(destination)
    }

    func newBatch() {
        guard phase != .running else { return }
        items.removeAll()
        runIDs = []
        phase = .idle
    }

    private func update(_ change: (inout Settings) -> Void) {
        change(&settings)
        settings.save(to: context.dataDirectory)
    }

    // MARK: Running

    func start() {
        guard canStart, let destination else { return }
        guard FileManager.default.isWritableFile(atPath: destination.path) else {
            context.showMessage("Vehla can't write to that folder. Choose another destination.")
            return
        }

        let work = items.filter(\.isPending)
        if let problem = Preflight.check(
            destinationBytes: work.reduce(0) { $0 + $1.size },
            stagingSizes: work.map { $0.compressesContents ? $0.largestFile : $0.size },
            parallel: BatchRunner.lightConcurrency + 1,
            destination: destination
        ) {
            notice = problem
            return
        }

        notice = nil
        phase = .running
        runIDs = work.map(\.id)
        unitOwners = []; unitSizes = []; unitProgress = []; unitResults = [:]; ownerUnits = [:]
        for item in work { setState(item.id, .working(0)) }
        CompressionEngine.resetNameReservations()
        let control = BatchControl()
        self.control = control
        keepAwake = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Compressing files"
        )

        let options = EngineOptions(quality: quality, fastVideo: fastVideo,
                                    trashOriginals: trashOriginals, trash: trashAction)
        let jobs = work.map { (id: $0.id, url: $0.url, isDirectory: $0.isDirectory,
                               size: $0.size, contents: $0.compressesContents) }

        task = Task { [weak self] in
            // Listing big folders can take a moment, so do it off the main thread.
            let planned: [(UUID, Result<[WorkUnit], Error>)] = await Task.detached {
                jobs.map { job in
                    guard job.contents else {
                        return (job.id, .success([WorkUnit(owner: job.id, source: job.url, isDirectory: job.isDirectory,
                                                           destination: destination, size: job.size)]))
                    }
                    return (job.id, Result { try FolderExpansion.units(for: job.url, owner: job.id, into: destination) })
                }
            }.value
            guard let model = self else { return }
            let units = model.prepare(planned)
            guard !Task.isCancelled else { model.finish(); return }

            await BatchRunner.run(
                units, options: options, control: control,
                progress: { index, value in Task { @MainActor in model.unitProgressed(index, value) } },
                finished: { index, result in await model.unitFinished(index, result) }
            )
            model.finish()
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Records which job belongs to which row; rows that couldn't be planned fail now.
    private func prepare(_ planned: [(UUID, Result<[WorkUnit], Error>)]) -> [WorkUnit] {
        var units: [WorkUnit] = []
        for (owner, outcome) in planned {
            switch outcome {
            case .success(let list):
                ownerUnits[owner] = Array(units.count..<(units.count + list.count))
                units += list
                if list.isEmpty { completeOwner(owner) }
            case .failure(let error):
                var failed = CompressionResult(status: .failed)
                failed.message = error.localizedDescription
                setState(owner, .done(failed))
            }
        }
        unitOwners = units.map(\.owner)
        unitSizes = units.map(\.size)
        unitProgress = Array(repeating: 0, count: units.count)
        return units
    }

    private func unitProgressed(_ index: Int, _ value: Double) {
        guard index < unitProgress.count, unitResults[index] == nil else { return }
        unitProgress[index] = value
        refreshOwner(unitOwners[index])
    }

    private func unitFinished(_ index: Int, _ result: CompressionResult) {
        guard index < unitProgress.count else { return }
        // A job stopped by Cancel goes back to the queue rather than showing as failed.
        if result.status == .failed, result.message == "Cancelled" { return }
        unitResults[index] = result
        unitProgress[index] = 1
        let owner = unitOwners[index]
        if ownerUnits[owner, default: []].allSatisfy({ unitResults[$0] != nil }) {
            completeOwner(owner)
        } else {
            refreshOwner(owner)
        }
    }

    private func refreshOwner(_ owner: UUID) {
        let indices = ownerUnits[owner, default: []]
        let total = indices.reduce(0.0) { $0 + Double(max(unitSizes[$1], 1)) }
        guard total > 0 else { return }
        let done = indices.reduce(0.0) { $0 + Double(max(unitSizes[$1], 1)) * unitProgress[$1] }
        setState(owner, .working(min(0.99, done / total)))
    }

    private func completeOwner(_ owner: UUID) {
        guard let item = items.first(where: { $0.id == owner }) else { return }
        let indices = ownerUnits[owner, default: []]
        let results = indices.compactMap { unitResults[$0] }
        guard item.compressesContents else {
            if let result = results.first { setState(owner, .done(result)) }
            return
        }
        var combined = FolderExpansion.aggregate(results, fileCount: indices.count)
        // Every file went to the Trash: the folder is now empty, so tidy it away too.
        if trashOriginals, combined.movedToTrash, results.count == indices.count,
           FolderExpansion.stats(of: item.url).files == 0 {
            if (try? trashAction(item.url)) != nil { combined.trashNote = "Original folder moved to the Trash." }
        }
        setState(owner, .done(combined))
    }

    func setState(_ id: FileItem.ID, _ state: FileItem.State) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
    }

    private func finish() {
        if let keepAwake { ProcessInfo.processInfo.endActivity(keepAwake) }
        keepAwake = nil

        // Rows that never finished (Cancel) go back to the queue; a folder that
        // was partly done keeps what it finished.
        for item in items where runIDs.contains(item.id) {
            guard case .working = item.state else { continue }
            let indices = ownerUnits[item.id, default: []]
            let results = indices.compactMap { unitResults[$0] }
            if item.compressesContents, !results.isEmpty {
                setState(item.id, .done(FolderExpansion.aggregate(results, fileCount: indices.count)))
            } else {
                setState(item.id, .pending)
            }
        }
        phase = .finished

        let done = runItems.compactMap { if case .done(let r) = $0.state { r } else { nil } }
        let compressed = done.filter { $0.status == .compressed }.count
        context.notify(
            title: "Compressor finished",
            body: compressed > 0
                ? "Saved \(Format.bytes(totalSaved)) across \(compressed) item\(compressed == 1 ? "" : "s")."
                : "Nothing could be made smaller without losing quality."
        )
        if openWhenDone, done.contains(where: { $0.status != .failed }) { openDestination() }
    }
}
