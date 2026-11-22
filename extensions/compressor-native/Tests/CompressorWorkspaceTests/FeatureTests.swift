import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

/// Parallel batches, Fast video, move-to-Trash and folder modes.
final class FeatureTests: XCTestCase {
    private var work: URL!
    private var trashBin: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("features-\(UUID().uuidString)", isDirectory: true)
        trashBin = work.appendingPathComponent("FakeTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashBin, withIntermediateDirectories: true)
        CompressionEngine.resetNameReservations()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    /// Stands in for the real Trash so tests never touch the user's.
    private var fakeTrash: @Sendable (URL) throws -> Void {
        let bin = trashBin!
        return { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        }
    }

    private func dir(_ name: String) throws -> URL {
        let url = work.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func ffmpeg(_ args: [String]) async throws {
        let path = try XCTUnwrap(Tools.find("ffmpeg"))
        let out = await runProcess(path, ["-v", "error", "-y"] + args)
        XCTAssertEqual(out.status, 0, out.stderr)
    }

    private func makeJPEG(_ url: URL, seed: Int = 1) async throws {
        try await ffmpeg(["-f", "lavfi", "-i", "mandelbrot=s=1200x800:start_scale=\(3 + Double(seed) * 0.1)",
                          "-frames:v", "1", "-q:v", "1", url.path])
    }

    private func text(_ url: URL) throws {
        try String(repeating: "compress me ", count: 40_000).write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: Parallel

    func testPoolNeverRunsMoreThanItsLimitAndRunsEverything() async {
        final class Counter: @unchecked Sendable {
            let lock = NSLock(); var now = 0; var peak = 0; var seen: [Int] = []
            func enter(_ i: Int) { lock.lock(); now += 1; peak = max(peak, now); seen.append(i); lock.unlock() }
            func leave() { lock.lock(); now -= 1; lock.unlock() }
        }
        let counter = Counter()
        await BatchRunner.runPool(Array(0..<12), limit: 3) { index in
            counter.enter(index)
            try? await Task.sleep(nanoseconds: 30_000_000)
            counter.leave()
        }
        XCTAssertEqual(counter.peak, 3, "should use exactly the allowed parallelism")
        XCTAssertEqual(counter.seen.sorted(), Array(0..<12))
    }

    func testParallelJobsWithTheSameNameNeverOverwriteEachOther() async throws {
        let destination = try dir("out")
        var units: [WorkUnit] = []
        for i in 0..<6 {
            let folder = try dir("src\(i)")
            let file = folder.appendingPathComponent("notes.txt")
            try text(file)
            units.append(WorkUnit(owner: UUID(), source: file, isDirectory: false, destination: destination, size: 1))
        }
        final class Box: @unchecked Sendable { let lock = NSLock(); var results: [CompressionResult] = []
            func add(_ r: CompressionResult) { lock.lock(); results.append(r); lock.unlock() } }
        let box = Box()
        await BatchRunner.run(units, options: EngineOptions(), progress: { _, _ in }, finished: { _, r in box.add(r) })

        XCTAssertEqual(box.results.count, 6)
        XCTAssertTrue(box.results.allSatisfy { $0.status == .compressed }, "\(box.results.map(\.message))")
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(names.count, 12, "6 originals + 6 zips, all distinct: \(names.sorted())")
        XCTAssertEqual(Set(box.results.compactMap(\.outputName)).count, 6)
    }

    func testPreflightCountsParallelStaging() throws {
        let values = try work.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = try XCTUnwrap(values.volumeAvailableCapacityForImportantUsage)
        let each = Int64(Double(free) * 0.12)
        // Destination needs 2 x 0.24 of the disk; staging one at a time fits, four at once doesn't.
        XCTAssertNil(Preflight.check(destinationBytes: each * 2, stagingSizes: [each, each], parallel: 1, destination: work))
        XCTAssertNotNil(Preflight.check(destinationBytes: each * 2, stagingSizes: [each, each, each, each], parallel: 4, destination: work))
    }

    // MARK: Fast video

    func testFastVideoUsesTheHardwareEncoder() async throws {
        let clip = try dir("in").appendingPathComponent("clip.mov")
        try await ffmpeg(["-f", "lavfi", "-i", "testsrc2=s=1920x1080:r=30", "-t", "3", "-c:v", "libx264", "-crf", "8", clip.path])
        let out = try dir("out")
        let result = await CompressionEngine(destination: out, fastVideo: true).compress(clip, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertNil(result.message, "no fallback should have been needed")

        let ffprobe = try XCTUnwrap(Tools.find("ffprobe"))
        let probe = await runProcess(ffprobe, ["-v", "error", "-select_streams", "v", "-show_entries",
                                               "stream=codec_name", "-of", "csv=p=0",
                                               out.appendingPathComponent(try XCTUnwrap(result.outputName)).path])
        XCTAssertEqual(probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hevc")
    }

    func testFastVideoFallsBackToTheStandardEncoder() async throws {
        let clip = try dir("in").appendingPathComponent("clip.mp4")
        try await ffmpeg(["-f", "lavfi", "-i", "testsrc2=s=1280x720:r=30", "-t", "2", "-c:v", "libx264", "-crf", "8", clip.path])
        var engine = CompressionEngine(destination: try dir("out"), fastVideo: true)
        engine.hardwareEncoder = "no_such_encoder"
        let result = await engine.compress(clip, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .compressed)
        XCTAssertEqual(result.message, "The hardware encoder couldn't handle this video, so the standard encoder was used.")
    }

    // MARK: Move originals to Trash

    func testOriginalIsTrashedOnlyAfterItsCopyIsVerified() async throws {
        let source = try dir("in").appendingPathComponent("notes.txt")
        try text(source)
        let out = try dir("out")
        let result = await CompressionEngine(destination: out, trashOriginal: true, trash: fakeTrash)
            .compress(source, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .compressed)
        XCTAssertTrue(result.movedToTrash)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "original should be in the Trash")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("notes.txt").path), "copy kept in destination")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trashBin.path).count, 1)
    }

    func testOriginalIsNeverTrashedWhenTheDestinationIsItsOwnFolder() async throws {
        let folder = try dir("same")
        let source = folder.appendingPathComponent("notes.txt")
        try text(source)
        let result = await CompressionEngine(destination: folder, trashOriginal: true, trash: fakeTrash)
            .compress(source, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .compressed)
        XCTAssertFalse(result.movedToTrash)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the only copy of the original must stay")
        XCTAssertEqual(result.trashNote, "Original kept: it is already in the destination folder.")
    }

    func testOriginalIsKeptWhenNothingWasCompressed() async throws {
        let source = try dir("in").appendingPathComponent("archive.zip")
        try Data((0..<50_000).map { _ in UInt8.random(in: 0...255) }).write(to: source)
        let result = await CompressionEngine(destination: try dir("out"), trashOriginal: true, trash: fakeTrash)
            .compress(source, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .alreadyCompressed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: Folder modes

    private func makeFolder() async throws -> URL {
        let folder = try dir("Holiday")
        let sub = folder.appendingPathComponent("Day 1", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try await makeJPEG(folder.appendingPathComponent("beach.jpg"), seed: 1)
        try await makeJPEG(sub.appendingPathComponent("sunset.jpg"), seed: 2)
        try text(sub.appendingPathComponent("notes.txt"))
        try "hidden".write(to: folder.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        return folder
    }

    func testCompressEachFileMirrorsTheFolderAndSkipsHiddenFiles() async throws {
        let folder = try await makeFolder()
        let out = try dir("out")
        let stats = FolderExpansion.stats(of: folder)
        XCTAssertEqual(stats.files, 3, "hidden files are not counted")

        let owner = UUID()
        let units = try FolderExpansion.units(for: folder, owner: owner, into: out)
        XCTAssertEqual(units.count, 3)
        final class Box: @unchecked Sendable { let lock = NSLock(); var results: [CompressionResult] = []
            func add(_ r: CompressionResult) { lock.lock(); results.append(r); lock.unlock() } }
        let box = Box()
        await BatchRunner.run(units, options: EngineOptions(), progress: { _, _ in }, finished: { _, r in box.add(r) })

        let fm = FileManager.default
        let mirror = out.appendingPathComponent("Holiday")
        for path in ["beach.jpg", "beach-compressed.jpg", "Day 1/sunset.jpg", "Day 1/sunset-compressed.jpg",
                     "Day 1/notes.txt", "Day 1/notes.txt.zip"] {
            XCTAssertTrue(fm.fileExists(atPath: mirror.appendingPathComponent(path).path), "missing \(path)")
        }
        XCTAssertFalse(fm.fileExists(atPath: mirror.appendingPathComponent(".DS_Store").path))

        let combined = FolderExpansion.aggregate(box.results, fileCount: units.count)
        XCTAssertEqual(combined.status, .compressed)
        XCTAssertEqual(combined.message, "3 of 3 files compressed")
        XCTAssertLessThan(combined.after, combined.before)
    }

    func testCompressEachFileNeverMergesIntoAnExistingFolder() throws {
        let folder = try dir("Holiday")
        try text(folder.appendingPathComponent("a.txt"))
        let out = try dir("out")
        try FileManager.default.createDirectory(at: out.appendingPathComponent("Holiday"), withIntermediateDirectories: true)
        let units = try FolderExpansion.units(for: folder, owner: UUID(), into: out)
        XCTAssertEqual(units.first?.destination.lastPathComponent, "Holiday (1)")
    }

    func testCompressEachFileRefusesADestinationInsideTheFolder() throws {
        let folder = try dir("Holiday")
        let inside = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        XCTAssertThrowsError(try FolderExpansion.units(for: folder, owner: UUID(), into: inside))
    }

    func testAggregateReportsFailuresAndCancellation() {
        var ok = CompressionResult(status: .compressed); ok.before = 100; ok.after = 40
        var bad = CompressionResult(status: .failed); bad.before = 50
        let combined = FolderExpansion.aggregate([ok, bad], fileCount: 5)
        XCTAssertEqual(combined.message, "1 of 5 files compressed, 1 failed, cancelled after 2")
        XCTAssertEqual(combined.savedBytes, 60)
    }
}

// MARK: - Through the window's model

@MainActor
final class ModelFeatureTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func makeModel(data: URL, confirm: @escaping () -> Bool = { true },
                           trash: @escaping @Sendable (URL) throws -> Void = { _ in XCTFail("unexpected trash") }) -> CompressorModel {
        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: data,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context, confirmTrash: confirm, trash: trash)
        model.openWhenDone = false
        return model
    }

    private func waitUntilFinished(_ model: CompressorModel) async throws {
        while model.phase == .running { try await Task.sleep(nanoseconds: 50_000_000) }
    }

    func testNewSettingsAreRememberedAndTrashNeedsConfirmation() {
        let data = work.appendingPathComponent("data")
        let declining = makeModel(data: data, confirm: { false })
        declining.setTrashOriginals(true)
        XCTAssertFalse(declining.trashOriginals, "declining the warning keeps it off")

        let model = makeModel(data: data)
        XCTAssertFalse(model.fastVideo)
        XCTAssertFalse(model.trashOriginals, "off by default")
        model.setFastVideo(true)
        model.setTrashOriginals(true)

        let again = makeModel(data: data)
        XCTAssertTrue(again.fastVideo)
        XCTAssertTrue(again.trashOriginals)
    }

    func testFolderModeChoiceIsRememberedForNewFolders() throws {
        let data = work.appendingPathComponent("data")
        let folder = work.appendingPathComponent("Docs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let model = makeModel(data: data)
        model.addFiles([folder])
        XCTAssertEqual(model.items.first?.folderMode, .zip, "zip stays the default")
        model.setFolderMode(try XCTUnwrap(model.items.first?.id), .contents)

        let again = makeModel(data: data)
        again.addFiles([folder])
        XCTAssertEqual(again.items.first?.folderMode, .contents)
        XCTAssertEqual(again.items.first?.typeLabel, "Folder · 1 file")
    }

    func testCompressEachFileWithTrashEndToEnd() async throws {
        let fm = FileManager.default
        let data = work.appendingPathComponent("data"), out = work.appendingPathComponent("out")
        let bin = work.appendingPathComponent("FakeTrash")
        for d in [data, out, bin] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))

        let folder = work.appendingPathComponent("Reports", isDirectory: true)
        try fm.createDirectory(at: folder.appendingPathComponent("2025"), withIntermediateDirectories: true)
        for name in ["a.txt", "b.txt", "2025/c.txt"] {
            try String(repeating: "report \(name) ", count: 30_000).write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let single = work.appendingPathComponent("single.txt")
        try String(repeating: "single ", count: 30_000).write(to: single, atomically: true, encoding: .utf8)

        let model = makeModel(data: data, trash: { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        })
        model.setTrashOriginals(true)
        model.addFiles([folder, single])
        model.setFolderMode(try XCTUnwrap(model.items.first?.id), .contents)
        model.start()
        XCTAssertEqual(model.phase, .running)
        try await waitUntilFinished(model)

        XCTAssertEqual(model.overallProgress, 1, accuracy: 0.0001)
        XCTAssertEqual(model.runCounts.done, 2)
        guard case .done(let folderResult) = model.items[0].state else { return XCTFail("folder not done") }
        XCTAssertEqual(folderResult.message, "3 of 3 files compressed")
        XCTAssertEqual(folderResult.trashNote, "Original folder moved to the Trash.")
        XCTAssertFalse(fm.fileExists(atPath: folder.path), "emptied folder goes to the Trash too")
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("Reports/2025/c.txt.zip").path))
        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("Reports/2025/c.txt").path), "verified copy kept")

        guard case .done(let singleResult) = model.items[1].state else { return XCTFail("file not done") }
        XCTAssertTrue(singleResult.movedToTrash)
        XCTAssertFalse(fm.fileExists(atPath: single.path))
    }
}
