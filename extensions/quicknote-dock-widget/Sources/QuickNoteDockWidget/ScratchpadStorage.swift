import Foundation
import CryptoKit

struct ScratchNote: Codable, Identifiable, Equatable, Sendable {
    var id = UUID().uuidString
    var content: String
    var created = Date()
    var modified = Date()
    var slot: Int?
    var deleted: Date?
    var importKey: String?
    var title: String { QuickNoteNote(id: id, content: content).title }
    var preview: String { QuickNoteNote(id: id, content: content).preview }
}

struct ScratchLibrary: Codable, Equatable, Sendable {
    var version = 1
    var revision: UInt64 = 0
    var notes: [ScratchNote] = []
    var selectedID: String?
    var expiryDays = 0
    var fontSize: Double = 15
    var linedPaper = false
    var mathResultColor: MathResultColor?
    var importedKeys: Set<String> = []

    func validate() throws {
        guard version == 1, notes.count <= 50_000,
              Set(notes.map(\.id)).count == notes.count,
              notes.allSatisfy({ $0.content.utf8.count <= QuickNoteDatabase.contentLimit && !$0.id.isEmpty }),
              [0, 1, 7, 30, 365].contains(expiryDays), (11...28).contains(fontSize),
              notes.allSatisfy({ $0.slot == nil || (1...9).contains($0.slot!) }) else {
            throw ScratchError.message("This library contains unsupported or oversized notes or settings.")
        }
        let slots = notes.filter { $0.deleted == nil }.compactMap(\.slot)
        guard Set(slots).count == slots.count else { throw ScratchError.message("Two notes occupy the same permanent slot.") }
    }

    /// Import keys this library already holds. A widget backup of this same
    /// library keys local notes as `vehla:<id>`, so those count as present too.
    func importedKeys(among keys: some Sequence<String?>) -> Set<String> {
        let localIDs = Set(notes.map(\.id))
        return Set(keys.compactMap { key -> String? in
            guard let key else { return nil }
            if importedKeys.contains(key) { return key }
            if key.hasPrefix("vehla:"), localIDs.contains(String(key.dropFirst(6))) { return key }
            return nil
        })
    }

    mutating func expire(now: Date = Date()) {
        guard expiryDays > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(expiryDays) * 86_400)
        for i in notes.indices where notes[i].slot == nil && notes[i].deleted == nil && notes[i].modified < cutoff {
            notes[i].deleted = now
        }
    }

    static func tutorials() -> ScratchLibrary {
        let texts = [
            "# A little room to think\n\nThis is your scratchpad in Vehla. Write a thought, paste a snippet, or work something out. Everything saves automatically on this Mac.\n\n⌘N makes a note. ⌘[ and ⌘] move through your stack; swiping works too. Search with ⌘F.\n\nUse the slot menu to keep a note in one of nine permanent spaces. Delete sends it to The Void, where you can restore it.\n\nImport Notes copies Antinote notes or a backup without changing the source. Antinote is optional.",
            "list: Before the next meeting\n[] Write down the one thing to decide\n[] Gather a link or two\n[x] Make room for a quick thought\n\n// Click a checkbox to toggle it. Return continues an item. Tab nests it.\n// Any note can use [] or - [ ] markers.",
            "math: A small weekend budget\ncoffee = 4.50\npeople = 6\ncoffee * people =\n(120 + 35) / 2 =\n100 + 15% =\n10 km to mi =\n20 c to f =\n\n// Results appear beside each expression. Variables update when earlier lines change.",
            "math: Scientific calculations\nx = pi / 4\nsin(x)^2 + cos(x)^2 =\nsin(rad(30)) =\ndeg(asin(0.5)) =\nsqrt(pow(3, 2) + pow(4, 2)) =\nlog(81, 3) =\nexp(ln(5)) =\n\n// Trig uses radians. rad converts degrees to radians; deg converts back. Variables flow down the note. End an expression with = to see its answer. Use * for multiplication.",
            "math: Function notation\nf(x) = 5x - 2\nf(1) =\nf(2) =\nf(3) =\nf(4) =\nf(5) =\nf(6) =\n\n// Each answer shows the input substituted into the rule, then the output. Change the rule to update every call below it.\n\nmath: Two inputs\narea(w, h) = w*h\narea(3, 4) =",
            "sum: Trip expenses\nTrain 28\nLunch 16.50\nMuseum 12\n\n// Try changing sum to average. Count reports words, characters and lines.",
            "# Collect, then let go\n\nType paste on a line and press Return to start AutoPaste. Copies are appended while this widget is visible. Escape or the stop button ends capture.\n\nPaste or drop an image to extract text locally with macOS Vision.\n\nType timer 5: Tea on a line and press Return to start a Vehla timer. Type timer for a stopwatch.\n\nUse Export for text, Markdown or a full library backup. Send to Vehla Notes keeps the thought that matters."
        ]
        var library = ScratchLibrary(notes: texts.map { ScratchNote(content: $0) })
        library.selectedID = library.notes.first?.id
        return library
    }
}

enum ScratchError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

/// Like ResearchRepository: serialized, atomic, package-private persistence.
/// Synchronous actor methods execute on the actor executor, never MainActor.
actor ScratchRepository {
    let root: URL
    private var savedRevision: UInt64?
    private let legacyRoot: URL?
    init(root: URL, legacyRoot: URL? = nil) {
        self.root = root
        self.legacyRoot = legacyRoot
    }

    /// Only the renamed package's sibling storage is eligible, never an arbitrary directory.
    static func legacyDirectory(for root: URL) -> URL? {
        guard root.lastPathComponent == "com.wiseman.vehla.quicknote" else { return nil }
        return root.deletingLastPathComponent().appendingPathComponent("com.wiseman.vehla.antinote")
    }
    private var file: URL { root.appendingPathComponent("scratchpad.json") }
    private var backup: URL { root.appendingPathComponent("scratchpad.previous.json") }
    static let byteLimit = 100 * 1_024 * 1_024

    static func read(_ url: URL) throws -> ScratchLibrary {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= byteLimit else { throw ScratchError.message("The library exceeds 100 MiB.") }
        let result = try JSONDecoder().decode(ScratchLibrary.self, from: Data(contentsOf: url))
        try result.validate()
        return result
    }

    func load() throws -> ScratchLibrary {
        if FileManager.default.fileExists(atPath: file.path) {
            let library = try Self.read(file)
            savedRevision = library.revision
            return library
        }
        guard !FileManager.default.fileExists(atPath: backup.path) else {
            throw ScratchError.message("Your library is missing. Choose Recover Previous Save in the menu.")
        }
        if let legacyRoot {
            let legacyFile = legacyRoot.appendingPathComponent("scratchpad.json")
            let legacyBackup = legacyRoot.appendingPathComponent("scratchpad.previous.json")
            // Copy the recovery snapshot first. A failed primary migration remains recoverable.
            if FileManager.default.fileExists(atPath: legacyBackup.path) {
                do {
                    _ = try Self.read(legacyBackup)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    try Data(contentsOf: legacyBackup).write(to: backup, options: .atomic)
                } catch {
                    // A damaged older snapshot must not block a valid current library.
                    guard FileManager.default.fileExists(atPath: legacyFile.path) else { throw error }
                }
            }
            if FileManager.default.fileExists(atPath: legacyFile.path) {
                let library = try Self.read(legacyFile)
                try save(library)
                return library
            }
            if FileManager.default.fileExists(atPath: backup.path) {
                throw ScratchError.message("Your previous library is missing. Choose Recover Previous Save in the menu.")
            }
        }
        let library = ScratchLibrary.tutorials()
        try save(library)
        return library
    }

    func save(_ library: ScratchLibrary) throws {
        if let savedRevision, library.revision <= savedRevision { return }
        try library.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(library)
        guard bytes.count <= Self.byteLimit else { throw ScratchError.message("Your library exceeds 100 MiB. Export and remove some notes.") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: file.path) {
            // Do not replace a good recovery copy with a corrupt primary file.
            if (try? Self.read(file)) != nil { try Data(contentsOf: file).write(to: backup, options: .atomic) }
        }
        try bytes.write(to: file, options: .atomic)
        savedRevision = library.revision
    }

    func recover() throws -> ScratchLibrary {
        var library = try Self.read(backup)
        library.revision = max(library.revision, savedRevision ?? 0) + 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(library)
        try bytes.write(to: file, options: .atomic)
        savedRevision = library.revision
        return library
    }
}

struct ImportPreview: Sendable {
    var source: String
    var notes: [ScratchNote]
    var message: String
}

/// Reuses the original Antinote SQLite discovery and schema parsers.
/// This actor only reads external files; no app launch or Accessibility work.
actor ScratchImporter {
    func discover(home: URL, installed: Bool) throws -> ImportPreview {
        try Task.checkCancellation()
        let found = QuickNoteDatabase.discover(home: home)
        if let best = QuickNoteDatabase.best(found) {
            return try database(best.url)
        }
        if let candidate = QuickNoteDatabase.locate(home: home) { return try database(candidate.url) }
        if let error = found.compactMap(\.error).first { throw ScratchError.message(error) }
        let containers = home.appendingPathComponent("Library/Containers")
        for bundle in ["com.chabomakers.Antinote", "com.chabomakers.Antinote-setapp"] {
            do { _ = try FileManager.default.contentsOfDirectory(at: containers.appendingPathComponent(bundle + "/Data"), includingPropertiesForKeys: nil) }
            catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
                    throw QuickNoteDatabaseError.permission("Alternatively, choose an exported file or SQLite backup you can access.")
                }
            }
        }
        return ImportPreview(source: "Antinote", notes: [], message: installed
            ? "Antinote is installed, but no readable notes were found. Choose its SQLite backup or exported text files. Your tutorials remain available."
            : "Antinote is not installed and no notes were found. You can use this scratchpad now, or choose a backup or exported files.")
    }

    func database(_ url: URL) throws -> ImportPreview {
        try Task.checkCancellation()
        let library = try QuickNoteDatabase.load(url)
        guard library.notes.count <= 50_000 else { throw ScratchError.message("Import supports up to 50,000 notes at once.") }
        let notes = library.notes.map { note in
            // Antinote identities are shared across stable, legacy and backup stores.
            ScratchNote(content: note.content, created: note.created ?? Date(), modified: note.modified ?? note.created ?? Date(),
                        slot: note.slot.flatMap { (0...8).contains($0) ? $0 + 1 : nil }, importKey: "antinote:\(UUID(uuidString: note.id)?.uuidString ?? note.id)")
        }
        return ImportPreview(source: url.lastPathComponent, notes: notes, message: notes.isEmpty
            ? "This database has no active notes to import. Your scratchpad is ready to use."
            : "Select notes to copy into Vehla. Existing imports and local edits are left untouched. The source database is never changed.")
    }

    func files(_ urls: [URL]) throws -> ImportPreview {
        var notes: [ScratchNote] = []
        for url in urls {
            try Task.checkCancellation()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= ScratchRepository.byteLimit else { throw ScratchError.message("\(url.lastPathComponent) exceeds 100 MiB.") }
            switch url.pathExtension.lowercased() {
            case "sqlite", "sqlite3", "db", "store": notes += try database(url).notes
            case "json":
                let library = try ScratchRepository.read(url)
                notes += library.notes.filter { $0.deleted == nil }.map { note in
                    var copy = note; copy.importKey = note.importKey ?? "vehla:\(note.id)"; copy.id = UUID().uuidString; return copy
                }
            case "txt", "md", "markdown":
                guard size <= QuickNoteDatabase.contentLimit else { throw ScratchError.message("\(url.lastPathComponent) exceeds the 2 MB note limit.") }
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else { throw ScratchError.message("\(url.lastPathComponent) is not UTF-8 text.") }
                let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                notes.append(ScratchNote(content: text, importKey: "text:\(hash)"))
            default: throw ScratchError.message("Choose SQLite, text, Markdown or a Vehla JSON backup.")
            }
            guard notes.count <= 50_000 else { throw ScratchError.message("Choose fewer than 50,000 notes per import.") }
        }
        return ImportPreview(source: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files", notes: notes,
                             message: "Choose the notes to import. Repeat imports skip existing identities and never overwrite your edits.")
    }

    func merged(_ incoming: [ScratchNote], library: ScratchLibrary) throws -> (ScratchLibrary, Int) {
        try Task.checkCancellation()
        var state = library
        let count = Self.merge(incoming, into: &state)
        try state.validate()
        try Task.checkCancellation()
        return (state, count)
    }

    static func merge(_ incoming: [ScratchNote], into library: inout ScratchLibrary) -> Int {
        var count = 0
        var occupied = Set(library.notes.filter { $0.deleted == nil }.compactMap(\.slot))
        let present = library.importedKeys(among: incoming.map(\.importKey))
        for var note in incoming {
            guard let key = note.importKey, !present.contains(key), !library.importedKeys.contains(key) else { continue }
            library.importedKeys.insert(key)
            note.id = UUID().uuidString
            if let slot = note.slot {
                if occupied.contains(slot) { note.slot = nil } else { occupied.insert(slot) }
            }
            library.notes.append(note)
            count += 1
        }
        return count
    }
}
