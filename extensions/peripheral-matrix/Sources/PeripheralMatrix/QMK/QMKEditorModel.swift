import AppKit
import Combine
import UniformTypeIdentifiers

struct QMKLayerPreset: Codable, Sendable {
    let formatVersion: Int
    let profileID: String
    let rows: Int
    let columns: Int
    let name: String
    let keycodes: [UInt16]
}

@MainActor final class QMKEditorModel: ObservableObject {
    @Published private(set) var baseline: VIAKeymapBackup?
    @Published private(set) var draft: [UInt16] = []
    @Published private(set) var profile: QMKKeyboardProfile?
    @Published private(set) var busy = false
    @Published private(set) var status: String?
    @Published private(set) var needsReload = false
    @Published var selectedLayer = 0
    @Published var selectedKey: Int?
    @Published private(set) var lastBackup: URL?
    private var session: VIAKeymapSession?
    private var dataDirectory: URL?
    private var task: Task<Void, Never>?
    var changes: [QMKKeyChange] { (try? VIAKeymapSession.changes(from: baseline?.keycodes ?? [], to: draft)) ?? [] }
    var canApply: Bool { !busy && !needsReload && baseline != nil && !changes.isEmpty }
    var keyboardIdentity: String? { baseline?.deviceIdentity }
    func load(endpoint: any VIAEndpoint, directory: URL) {
        guard !busy else { return }
        guard let profile = endpoint.keymapProfile else { status = "Keymap editing currently supports Keychron K10 Pro ANSI White (3434:02A3)."; return }
        self.profile = profile; session = VIAKeymapSession(endpoint: endpoint, profile: profile); dataDirectory = directory
        baseline = nil; draft = []; lastBackup = nil; needsReload = false; busy = true; status = "Reading mapping and preserving macros…"
        task = Task { [weak self] in
            guard let self, let session = self.session else { return }
            do {
                let snapshot = try await session.load()
                guard !Task.isCancelled else { return }
                self.baseline = snapshot; self.draft = snapshot.keycodes
                self.selectedLayer = min(self.selectedLayer, profile.layers - 1)
                self.selectedKey = profile.keys.first?.id
                self.status = "Loaded \(profile.layers) layers. Edits stay in the draft until Apply."
            } catch { self.status = error.localizedDescription; self.needsReload = true }
            self.busy = false; self.task = nil
        }
    }
    func waitForOperation() async { await task?.value }
    func code(for key: Int, layer: Int? = nil) -> UInt16 {
        guard let profile else { return 0 }
        let offset = (layer ?? selectedLayer) * profile.keysPerLayer + key
        return draft.indices.contains(offset) ? draft[offset] : 0
    }
    func assign(_ code: UInt16) {
        guard !busy, !needsReload, let profile, (0..<profile.layers).contains(selectedLayer), let key = selectedKey,
              profile.keys.contains(where: { $0.id == key }) else { return }
        do { try QMKKeycodes.validate(code, layerCount: profile.layers, macroCount: baseline?.macroCount) }
        catch { status = error.localizedDescription; return }
        let offset = selectedLayer * profile.keysPerLayer + key
        guard draft.indices.contains(offset) else { return }
        draft[offset] = code; status = "\(changes.count) key assignments in the draft."
    }
    func copyLayer(from source: Int) {
        guard !busy, !needsReload, let profile, baseline != nil, (0..<profile.layers).contains(selectedLayer), (0..<profile.layers).contains(source), source != selectedLayer else { return }
        for key in profile.keys { draft[selectedLayer * profile.keysPerLayer + key.id] = draft[source * profile.keysPerLayer + key.id] }
        status = "Copied layer \(source) into the draft for layer \(selectedLayer)."
    }
    func discard() { guard !busy, let baseline else { return }; draft = baseline.keycodes; status = "Draft discarded." }
    func apply() {
        guard canApply, let session, let baseline, let directory = dataDirectory else { return }
        let proposed = draft
        busy = true; status = "Backing up, writing changed keys, and verifying…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let (saved, backup) = try await session.apply(baseline: baseline, draft: proposed, backupDirectory: directory.appendingPathComponent("qmk-backups"))
                self.baseline = saved; self.draft = saved.keycodes; self.lastBackup = backup
                self.status = "Saved and verified. Your macros are unchanged."
            } catch { self.status = error.localizedDescription; self.needsReload = true }
            self.busy = false; self.task = nil
        }
    }
    func invalidate() { needsReload = true; status = "Keyboard disconnected or the bridge stopped. Reconnect and load the keymap again." }
    func exportLayer(name: String) {
        guard !busy, let profile, baseline != nil, (0..<profile.layers).contains(selectedLayer) else { return }
        let start = selectedLayer * profile.keysPerLayer
        let preset = QMKLayerPreset(formatVersion: 1, profileID: profile.id, rows: profile.rows, columns: profile.columns,
            name: name, keycodes: Array(draft[start..<(start + profile.keysPerLayer)]))
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Layer-\(selectedLayer).vehla-layer.json"
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                do { try JSONEncoder().encode(preset).write(to: url, options: .atomic); self?.status = "Layer draft exported." }
                catch { self?.status = error.localizedDescription }
            }
        }
    }
    func importLayer() {
        guard !busy, baseline != nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                do { let data = try await Self.readDocument(url, maximumBytes: 65_536); try self?.importLayer(data: data) }
                catch { self?.status = error.localizedDescription }
            }
        }
    }
    func importLayer(data: Data) throws {
        guard !busy, !needsReload, let profile, baseline != nil, (0..<profile.layers).contains(selectedLayer), data.count <= 65_536 else { throw VIAError.message("Load the keyboard before importing a layer file.") }
        let preset = try JSONDecoder().decode(QMKLayerPreset.self, from: data)
        guard preset.formatVersion == 1, preset.profileID == profile.id, preset.rows == profile.rows,
              preset.columns == profile.columns, preset.keycodes.count == profile.keysPerLayer else { throw VIAError.message("This layer file belongs to a different keyboard layout.") }
        for code in preset.keycodes { try QMKKeycodes.validate(code, layerCount: profile.layers, macroCount: baseline?.macroCount) }
        for key in profile.keys { draft[selectedLayer * profile.keysPerLayer + key.id] = preset.keycodes[key.id] }
        status = "Imported \(preset.name) into the draft. Apply to save to the keyboard."
    }
    func restoreBackup() {
        guard !busy, baseline != nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        if let directory = dataDirectory { panel.directoryURL = directory.appendingPathComponent("qmk-backups") }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                do { let data = try await Self.readDocument(url, maximumBytes: 131_072); try self?.restoreBackup(data: data) }
                catch { self?.status = error.localizedDescription }
            }
        }
    }
    func restoreBackup(data: Data) throws {
        guard !busy, !needsReload, let profile, let baseline, data.count <= 131_072 else { throw VIAError.message("Reload the current keyboard before restoring.") }
        let backup = try JSONDecoder().decode(VIAKeymapBackup.self, from: data)
        guard backup.formatVersion == 1, backup.profileID == profile.id, backup.protocolVersion == 12,
              backup.rows == profile.rows, backup.columns == profile.columns, backup.layers == profile.layers,
              backup.keycodes.count == baseline.keycodes.count else { throw VIAError.message("Backup does not match this keyboard's firmware geometry.") }
        for code in backup.keycodes { try QMKKeycodes.validate(code, layerCount: profile.layers, macroCount: baseline.macroCount) }
        for layer in 0..<profile.layers {
            for key in profile.keys { draft[layer * profile.keysPerLayer + key.id] = backup.keycodes[layer * profile.keysPerLayer + key.id] }
        }
        status = "Backup mapping loaded into the draft. Review, then Apply. Current macros are preserved."
    }
    private static func readDocument(_ url: URL, maximumBytes: Int) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else { throw VIAError.message("The file is too large for a layer or backup document.") }
            return data
        }.value
    }
    func showBackups() {
        guard let directory = dataDirectory else { return }
        let backups = directory.appendingPathComponent("qmk-backups")
        guard FileManager.default.fileExists(atPath: backups.path) else { status = "Backups are created before Apply."; return }
        NSWorkspace.shared.open(backups)
    }
}
