import Foundation

// MARK: - File kinds

enum MediaKind: String, Sendable {
    case jpeg, png, heic, webp, pdf, video, generic, skip

    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "webm"]
    private static let compressedExtensions: Set<String> = [
        "zip", "gz", "bz2", "xz", "7z", "rar", "dmg", "docx", "xlsx", "pptx",
        "mp3", "m4a", "aac", "flac", "ogg", "gif",
    ]

    static func classify(_ url: URL, isDirectory: Bool) -> MediaKind {
        if isDirectory { return .generic }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "heic": return .heic
        case "webp": return .webp
        case "pdf": return .pdf
        case let ext where videoExtensions.contains(ext): return .video
        case let ext where compressedExtensions.contains(ext): return .skip
        default: return .generic
        }
    }

    var label: String {
        switch self {
        case .jpeg, .png, .heic, .webp: "Image"
        case .pdf: "PDF"
        case .video: "Video"
        case .generic: "File"
        case .skip: "Compressed file"
        }
    }

    var symbol: String {
        switch self {
        case .jpeg, .png, .heic, .webp: "photo"
        case .pdf: "doc.richtext"
        case .video: "film"
        case .generic: "doc.zipper"
        case .skip: "doc.fill"
        }
    }
}

// MARK: - Quality

/// How hard to compress. Balanced is the visually-lossless default.
enum QualityPreset: String, CaseIterable, Identifiable, Sendable {
    case smaller, balanced, best

    var id: String { rawValue }

    var label: String {
        switch self {
        case .smaller: "Smaller"
        case .balanced: "Balanced"
        case .best: "Best quality"
        }
    }

    var detail: String {
        switch self {
        case .smaller: "Smallest files, a slight quality trade-off"
        case .balanced: "Recommended: visually lossless"
        case .best: "Highest fidelity, larger files"
        }
    }

    var videoCRF: Int {
        switch self { case .smaller: 28; case .balanced: 24; case .best: 20 }
    }
    var jpegQuality: Int {
        switch self { case .smaller: 75; case .balanced: 85; case .best: 92 }
    }
    var heicQuality: Int {
        switch self { case .smaller: 70; case .balanced: 80; case .best: 90 }
    }
    var webpQuality: Int {
        switch self { case .smaller: 75; case .balanced: 85; case .best: 92 }
    }
    /// Ghostscript presets: /ebook downsamples to 150 dpi, /printer and
    /// /prepress keep 300 dpi (prepress also keeps colour fidelity).
    var pdfSettings: String {
        switch self { case .smaller: "/ebook"; case .balanced: "/printer"; case .best: "/prepress" }
    }
}

// MARK: - Results

struct CompressionResult: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case compressed, alreadyOptimal, alreadyCompressed, failed
    }

    var status: Status
    var before: Int64 = 0
    var after: Int64 = 0
    var outputName: String?
    var message: String?

    var savedBytes: Int64 { status == .compressed ? before - after : 0 }

    var savedFraction: Double {
        guard status == .compressed, before > 0 else { return 0 }
        return 1 - Double(after) / Double(before)
    }
}

private struct EngineError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

// MARK: - Running tools

struct ProcessOutput: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
}

private final class LockedText: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""
    func append(_ text: String) { lock.lock(); value += text; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return value }
}

private final class LineSplitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    func feed(_ text: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        pending += text
        var lines = pending.components(separatedBy: "\n")
        pending = lines.removeLast()
        return lines
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process = Process()
}

enum Tools {
    static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func find(_ name: String) -> String? {
        searchDirectories
            .map { "\($0)/\(name)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func require(_ name: String, hint: String) throws -> String {
        guard let path = find(name) else {
            throw EngineError(message: "\(name) is not installed. \(hint)")
        }
        return path
    }
}

/// Runs a tool without a shell. Cancelling the surrounding task terminates it.
func runProcess(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: URL? = nil,
    onStdoutLine: (@Sendable (String) -> Void)? = nil
) async -> ProcessOutput {
    let box = ProcessBox()
    let process = box.process
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    process.standardInput = FileHandle.nullDevice

    let outText = LockedText()
    let errText = LockedText()
    let splitter = LineSplitter()

    outPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
        outText.append(text)
        if let onStdoutLine { splitter.feed(text).forEach(onStdoutLine) }
    }
    errPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty, let text = String(data: data, encoding: .utf8) { errText.append(text) }
    }

    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? outPipe.fileHandleForReading.readToEnd(),
                   let text = String(data: rest, encoding: .utf8) { outText.append(text) }
                if let rest = try? errPipe.fileHandleForReading.readToEnd(),
                   let text = String(data: rest, encoding: .utf8) { errText.append(text) }
                continuation.resume(returning: ProcessOutput(
                    status: finished.terminationStatus,
                    stdout: outText.text,
                    stderr: errText.text
                ))
            }
            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ProcessOutput(
                    status: -1, stdout: "", stderr: error.localizedDescription
                ))
            }
        }
    } onCancel: {
        if box.process.isRunning { box.process.terminate() }
    }
}

// MARK: - Engine

struct CompressionEngine: Sendable {
    let destination: URL
    var quality: QualityPreset = .balanced

    /// A result must be at least this much smaller than the original to be kept.
    static let minimumSaving = 0.97

    /// Audio that is safe to copy untouched: no quality loss, and the only
    /// option for codecs ffmpeg cannot decode, such as the iPhone's spatial
    /// "apple_apac".
    static let copyableAudio: Set<String> = ["aac", "apple_apac", "alac", "ac3", "eac3", "mp3"]

    private struct Plan {
        var outputName: String
        var executable: String
        var arguments: @Sendable (_ input: URL, _ output: URL) -> [String]
        var isZip = false
    }

    /// Compresses one item and saves a copy of the original beside the result.
    func compress(
        _ source: URL,
        isDirectory: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async -> CompressionResult {
        var result = CompressionResult(status: .failed)
        let fm = FileManager.default
        let kind = MediaKind.classify(source, isDirectory: isDirectory)

        do {
            result.before = Self.size(of: source)

            if isDirectory, Self.isInside(destination, source) {
                throw EngineError(message: "The destination folder is inside the folder being compressed.")
            }
            if kind == .skip {
                _ = try copyOriginal(source)
                result.status = .alreadyCompressed
                result.after = result.before
                result.message = "Already compressed. Only the original was saved."
                return result
            }

            // Helper tools work on a private copy in the temp folder, so only
            // this process touches the user's folders.
            let stage = fm.temporaryDirectory
                .appendingPathComponent("vehla-compressor-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stage) }

            let stagedIn = stage.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: stagedIn)
            try Task.checkCancellation()

            let plan = try await makePlan(kind, source: source, stagedIn: stagedIn)
            let finalURL = Self.uniqueURL(in: destination, name: plan.outputName)
            let stagedOut = stage.appendingPathComponent("result.\(finalURL.pathExtension)")

            let output: ProcessOutput
            if plan.isZip {
                let target = isDirectory ? "./\(stagedIn.lastPathComponent)" : stagedIn.path
                let flags = isDirectory ? ["-9", "-q", "-r", "-X"] : ["-9", "-q", "-X", "-j"]
                output = await runProcess(plan.executable, flags + [stagedOut.path, target], currentDirectory: stage)
            } else {
                var duration: Double?
                if kind == .video { duration = await Self.videoDuration(stagedIn) }
                output = await runProcess(
                    plan.executable,
                    plan.arguments(stagedIn, stagedOut),
                    onStdoutLine: kind == .video ? Self.progressParser(duration: duration, progress) : nil
                )
            }
            try Task.checkCancellation()

            guard output.status == 0 else {
                let detail = output.stderr
                    .split(separator: "\n").suffix(3).joined(separator: " | ")
                throw EngineError(message: "\(URL(fileURLWithPath: plan.executable).lastPathComponent) failed: \(detail.isEmpty ? "exit \(output.status)" : detail)")
            }

            let after = Self.size(of: stagedOut)
            _ = try copyOriginal(source)

            if Double(after) < Double(result.before) * Self.minimumSaving {
                let partial = destination.appendingPathComponent(".\(finalURL.lastPathComponent).partial")
                do {
                    try fm.copyItem(at: stagedOut, to: partial)
                    try fm.moveItem(at: partial, to: finalURL)
                } catch {
                    try? fm.removeItem(at: partial)
                    throw error
                }
                result.status = .compressed
                result.after = after
                result.outputName = finalURL.lastPathComponent
            } else {
                result.status = .alreadyOptimal
                result.after = result.before
                result.message = "Already well optimised. Only the original was saved."
            }
            progress(1)
            return result
        } catch is CancellationError {
            result.message = "Cancelled"
            return result
        } catch {
            result.message = Self.friendly(error, destination: destination)
            return result
        }
    }

    // MARK: Plans

    private func makePlan(_ kind: MediaKind, source: URL, stagedIn: URL) async throws -> Plan {
        let stem = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        let name = "\(stem)-compressed.\(ext)"
        let q = quality

        switch kind {
        case .jpeg:
            return Plan(outputName: name, executable: "/usr/bin/sips") {
                ["-s", "format", "jpeg", "-s", "formatOptions", "\(q.jpegQuality)", $0.path, "--out", $1.path]
            }
        case .heic:
            return Plan(outputName: name, executable: "/usr/bin/sips") {
                ["-s", "format", "heic", "-s", "formatOptions", "\(q.heicQuality)", $0.path, "--out", $1.path]
            }
        case .webp:
            let cwebp = try Tools.require("cwebp", hint: "Install it with: brew install webp")
            return Plan(outputName: name, executable: cwebp) {
                ["-q", "\(q.webpQuality)", "-m", "6", "-metadata", "none", $0.path, "-o", $1.path]
            }
        case .png:
            if let oxipng = Tools.find("oxipng") {
                return Plan(outputName: name, executable: oxipng) {
                    ["-o", "4", "--strip", "safe", "--out", $1.path, $0.path]
                }
            }
            let ffmpeg = try Tools.require("ffmpeg", hint: "Install it with: brew install ffmpeg")
            return Plan(outputName: name, executable: ffmpeg) {
                ["-v", "error", "-y", "-i", $0.path, "-c:v", "png", "-compression_level", "9", "-pred", "mixed", $1.path]
            }
        case .pdf:
            let gs = try Tools.require("gs", hint: "Install it with: brew install ghostscript")
            return Plan(outputName: name, executable: gs) {
                ["-sDEVICE=pdfwrite", "-dCompatibilityLevel=1.6", "-dPDFSETTINGS=\(q.pdfSettings)",
                 "-dDetectDuplicateImages=true", "-dCompressFonts=true",
                 "-dNOPAUSE", "-dQUIET", "-dBATCH", "-sOutputFile=\($1.path)", $0.path]
            }
        case .video:
            let ffmpeg = try Tools.require("ffmpeg", hint: "Install it with: brew install ffmpeg")
            let codecs = await Self.audioCodecs(stagedIn)
            let copyAudio = !codecs.isEmpty && codecs.allSatisfy(Self.copyableAudio.contains)
            let container = codecs.contains("apple_apac") ? "mov" : "mp4" // APAC only lives in QuickTime
            return Plan(outputName: "\(stem)-compressed.\(container)", executable: ffmpeg) {
                ["-v", "error", "-y", "-progress", "pipe:1", "-nostats", "-i", $0.path,
                 "-map", "0:v:0", "-map", "0:a?", "-sn", "-dn",
                 "-c:v", "libx265", "-crf", "\(q.videoCRF)", "-preset", "medium", "-tag:v", "hvc1"]
                + (copyAudio ? ["-c:a", "copy"] : ["-c:a", "aac", "-b:a", "160k"])
                + ["-movflags", "+faststart", $1.path]
            }
        case .generic, .skip:
            return Plan(
                outputName: "\(source.lastPathComponent).zip",
                executable: "/usr/bin/zip",
                arguments: { _, _ in [] },
                isZip: true
            )
        }
    }

    private static func audioCodecs(_ url: URL) async -> [String] {
        guard let ffprobe = Tools.find("ffprobe") else { return [] }
        let out = await runProcess(ffprobe, ["-v", "error", "-select_streams", "a",
                                             "-show_entries", "stream=codec_name", "-of", "csv=p=0", url.path])
        return out.stdout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func videoDuration(_ url: URL) async -> Double? {
        guard let ffprobe = Tools.find("ffprobe") else { return nil }
        let out = await runProcess(ffprobe, ["-v", "error", "-show_entries", "format=duration",
                                             "-of", "csv=p=0", url.path])
        return Double(out.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func progressParser(
        duration: Double?,
        _ progress: @escaping @Sendable (Double) -> Void
    ) -> @Sendable (String) -> Void {
        { line in
            guard let duration, duration > 0, line.hasPrefix("out_time_us="),
                  let micros = Double(line.dropFirst("out_time_us=".count)) else { return }
            progress(min(0.99, max(0, micros / 1_000_000 / duration)))
        }
    }

    // MARK: Files

    private func copyOriginal(_ source: URL) throws -> String? {
        let parent = source.deletingLastPathComponent().standardizedFileURL.path
        if parent == destination.standardizedFileURL.path { return nil } // already there
        let target = Self.uniqueURL(in: destination, name: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: target)
        return target.lastPathComponent
    }

    /// "photo.jpg" -> "photo (1).jpg" when the name is taken.
    static func uniqueURL(in directory: URL, name: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 1
        repeat {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)")
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return Int64((try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let walker = fm.enumerator(at: url, includingPropertiesForKeys: keys) {
            for case let child as URL in walker {
                let values = try? child.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
            }
        }
        return total
    }

    private static func isInside(_ child: URL, _ parent: URL) -> Bool {
        let c = child.standardizedFileURL.path, p = parent.standardizedFileURL.path
        return c == p || c.hasPrefix(p + "/")
    }

    private static func friendly(_ error: Error, destination: URL) -> String {
        let ns = error as NSError
        let blocked = ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code)
            || ns.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(ns.code)
        if blocked {
            return "macOS blocked access to \(destination.path). Allow Vehla under System Settings → Privacy & Security → Files & Folders."
        }
        return error.localizedDescription
    }
}

// MARK: - Free space

enum Preflight {
    /// Each file is staged in the temp folder (its size, plus the result) and
    /// then saved to the destination beside a copy of the original, so a batch
    /// needs about twice its size in the destination and twice its largest
    /// file in temp. Returns a message when there isn't room, else nil.
    static func check(sizes: [Int64], destination: URL, temporary: URL = FileManager.default.temporaryDirectory) -> String? {
        guard let largest = sizes.max() else { return nil }
        let margin = 1.05
        let destinationNeeded = Int64(Double(sizes.reduce(0, +)) * 2 * margin)
        let temporaryNeeded = Int64(Double(largest) * 2 * margin)

        func available(_ url: URL) -> (free: Int64, volume: URL?)? {
            let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeURLKey]
            guard let values = try? url.resourceValues(forKeys: keys),
                  let free = values.volumeAvailableCapacityForImportantUsage else { return nil }
            return (free, values.volume)
        }
        guard let dest = available(destination), let temp = available(temporary) else { return nil }

        if let a = dest.volume, let b = temp.volume, a == b {
            let needed = destinationNeeded + temporaryNeeded
            return dest.free >= needed ? nil
                : "Not enough free space: this batch needs about \(Format.bytes(needed)) and the disk has \(Format.bytes(dest.free))."
        }
        if dest.free < destinationNeeded {
            return "Not enough room in the destination folder: it needs about \(Format.bytes(destinationNeeded)) and has \(Format.bytes(dest.free))."
        }
        if temp.free < temporaryNeeded {
            return "Not enough free space on your startup disk for working files: needs about \(Format.bytes(temporaryNeeded)) and has \(Format.bytes(temp.free))."
        }
        return nil
    }
}

// MARK: - Formatting

enum Format {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
