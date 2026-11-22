import Foundation

/// What to do with a folder that is added to the batch.
enum FolderMode: String, CaseIterable, Identifiable, Sendable {
    /// One lossless zip of the whole folder.
    case zip
    /// Compress every file inside, mirroring the folder in the destination.
    case contents

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zip: "Zip folder"
        case .contents: "Compress each file"
        }
    }
}

/// One file (or folder to zip) for the engine, and the row it belongs to.
struct WorkUnit: Sendable {
    let owner: UUID
    let source: URL
    let isDirectory: Bool
    let destination: URL
    let size: Int64

    var isVideo: Bool { MediaKind.classify(source, isDirectory: isDirectory) == .video }
}

struct EngineOptions: Sendable {
    var quality: QualityPreset = .balanced
    var fastVideo = false
    var trashOriginals = false
    var trash: @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }

    func engine(for destination: URL) -> CompressionEngine {
        CompressionEngine(destination: destination, quality: quality, fastVideo: fastVideo,
                          trashOriginal: trashOriginals, trash: trash)
    }
}

/// Lets the window stop one row's jobs mid-batch without stopping the rest.
final class BatchControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped: Set<UUID> = []
    private var running: [Int: (owner: UUID, task: Task<CompressionResult, Never>)] = [:]

    func isStopped(_ owner: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(owner)
    }

    /// Skips the row's queued jobs and cancels the ones already running.
    func stop(_ owner: UUID) {
        lock.lock()
        stopped.insert(owner)
        let tasks = running.values.filter { $0.owner == owner }.map(\.task)
        lock.unlock()
        tasks.forEach { $0.cancel() }
    }

    fileprivate func register(_ index: Int, owner: UUID, task: Task<CompressionResult, Never>) {
        lock.lock()
        let alreadyStopped = stopped.contains(owner)
        if !alreadyStopped { running[index] = (owner, task) }
        lock.unlock()
        if alreadyStopped { task.cancel() }
    }

    fileprivate func unregister(_ index: Int) {
        lock.lock(); running[index] = nil; lock.unlock()
    }
}

enum BatchRunner {
    /// Images, PDFs and zips that may run at the same time. Video gets its own
    /// lane, one at a time, because the encoder already uses every core.
    static let lightConcurrency = min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 4))

    static func run(
        _ units: [WorkUnit],
        options: EngineOptions,
        control: BatchControl = BatchControl(),
        progress: @escaping @Sendable (Int, Double) -> Void,
        finished: @escaping @Sendable (Int, CompressionResult) async -> Void
    ) async {
        let work: @Sendable (Int) async -> Void = { index in
            let unit = units[index]
            guard !control.isStopped(unit.owner) else { return }
            progress(index, 0)
            let engine = options.engine(for: unit.destination)
            let job = Task { await engine.compress(unit.source, isDirectory: unit.isDirectory) { progress(index, $0) } }
            control.register(index, owner: unit.owner, task: job)
            let result = await withTaskCancellationHandler { await job.value } onCancel: { job.cancel() }
            control.unregister(index)
            guard !control.isStopped(unit.owner) else { return }
            await finished(index, result)
        }
        let videos = units.indices.filter { units[$0].isVideo }
        let others = units.indices.filter { !units[$0].isVideo }
        await withTaskGroup(of: Void.self) { lanes in
            lanes.addTask { await runPool(others, limit: lightConcurrency, work) }
            lanes.addTask { await runPool(videos, limit: 1, work) }
        }
    }

    /// Runs `work` for each index, never more than `limit` at once, in order.
    static func runPool(_ indices: [Int], limit: Int, _ work: @escaping @Sendable (Int) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            var next = indices.makeIterator()
            for _ in 0..<max(1, limit) {
                guard let index = next.next() else { break }
                group.addTask { await work(index) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let index = next.next() else { continue }
                group.addTask { await work(index) }
            }
        }
    }
}

// MARK: - Folders compressed file by file

enum FolderExpansion {
    struct Stats: Sendable {
        var bytes: Int64 = 0
        var files = 0
        var largest: Int64 = 0
    }

    /// Size, file count and largest file, counting what `units` would process.
    static func stats(of folder: URL) -> Stats {
        var stats = Stats()
        for (url, _) in entries(in: folder) {
            let size = CompressionEngine.size(of: url)
            stats.bytes += size
            stats.files += 1
            stats.largest = max(stats.largest, size)
        }
        return stats
    }

    /// One unit per file, each saved into a mirror of the folder inside
    /// `destination` ("Photos" -> "Destination/Photos/…"). Hidden files and
    /// symbolic links are skipped; packages such as .app bundles are zipped whole.
    static func units(for folder: URL, owner: UUID, into destination: URL) throws -> [WorkUnit] {
        if CompressionEngine.isInside(destination, folder) {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "The destination folder is inside the folder being compressed.",
            ])
        }
        let fm = FileManager.default
        let root = CompressionEngine.uniqueURL(in: destination, name: folder.lastPathComponent)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let base = folder.standardizedFileURL.path
        var units: [WorkUnit] = []
        for (url, isDirectory) in entries(in: folder) {
            let relativeParent = String(url.deletingLastPathComponent().standardizedFileURL.path.dropFirst(base.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = relativeParent.isEmpty ? root : root.appendingPathComponent(relativeParent, isDirectory: true)
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            units.append(WorkUnit(owner: owner, source: url, isDirectory: isDirectory,
                                  destination: target, size: CompressionEngine.size(of: url)))
        }
        return units
    }

    /// Finder metadata that is regenerated on demand and carries no user content.
    private static let disposable: Set<String> = [".DS_Store", ".localized"]

    /// Everything still inside `folder` that "Compress each file" never copied
    /// to the mirror: hidden files, symbolic links, and packages or files that
    /// were added since. A folder with leftovers is not empty and must not be
    /// trashed, or those items would exist nowhere else.
    static func leftovers(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }
        var found: [URL] = []
        for case let url as URL in walker where !disposable.contains(url.lastPathComponent) {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true || values?.isPackage == true || values?.isRegularFile == true {
                found.append(url)
            }
        }
        return found
    }

    /// Regular files, plus packages treated as single items.
    private static func entries(in folder: URL) -> [(URL, Bool)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey]
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var found: [(URL, Bool)] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            if values?.isPackage == true { found.append((url, true)); continue }
            if values?.isRegularFile == true { found.append((url, false)) }
        }
        return found
    }

    /// Combines a folder's per-file results into the single row the user sees.
    static func aggregate(_ results: [CompressionResult], fileCount: Int) -> CompressionResult {
        let compressed = results.filter { $0.status == .compressed }.count
        let failed = results.filter { $0.status == .failed }.count
        var combined = CompressionResult(status: .alreadyOptimal)
        combined.before = results.reduce(0) { $0 + $1.before }
        combined.after = results.reduce(0) { $0 + ($1.status == .compressed ? $1.after : $1.before) }
        combined.fileCount = fileCount
        combined.failedCount = failed

        if fileCount == 0 {
            combined.message = "The folder has no files to compress."
        } else if compressed > 0 {
            combined.status = .compressed
        } else if failed == results.count {
            combined.status = .failed
        }
        var parts = ["\(compressed) of \(fileCount) file\(fileCount == 1 ? "" : "s") compressed"]
        if failed > 0 { parts.append("\(failed) failed") }
        if results.count < fileCount { parts.append("cancelled after \(results.count)") }
        if fileCount > 0 { combined.message = parts.joined(separator: ", ") }

        let trashed = results.filter(\.movedToTrash).count
        if trashed > 0 { combined.trashNote = "\(trashed) original\(trashed == 1 ? "" : "s") moved to the Trash." }
        combined.movedToTrash = trashed > 0 && trashed == fileCount
        return combined
    }
}
