import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

/// "Move originals to Trash" must only ever trash something whose exact bytes
/// are safely in the destination.
final class TrashSafetyTests: XCTestCase {
    private var work: URL!
    private var bin: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("trash-safety-\(UUID().uuidString)", isDirectory: true)
        bin = work.appendingPathComponent("FakeTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        CompressionEngine.resetNameReservations()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private var fakeTrash: @Sendable (URL) throws -> Void {
        let bin = bin!
        return { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        }
    }

    private func dir(_ name: String) throws -> URL {
        let url = work.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file that is still being written (a download, an iCloud sync, a
    /// recording that hasn't finished) changes while Compressor works on its
    /// snapshot. The snapshot is what got compressed, so the original must not
    /// be trashed on the strength of that stale output.
    func testOriginalIsKeptWhenItChangesDuringCompression() async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let source = try dir("in").appendingPathComponent("recording.mov")
        let out = try dir("out")
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=1920x1080:r=30",
                                      "-vf", "noise=alls=8:allf=t", "-t", "4", "-c:v", "libx264", "-crf", "8",
                                      "-preset", "ultrafast", source.path])
        let originalBytes = try Data(contentsOf: source)

        // Overwrite the source the first time the encoder reports progress,
        // which is guaranteed to be after the snapshot was taken.
        final class Once: @unchecked Sendable {
            let lock = NSLock(); var done = false
            func run(_ body: () -> Void) { lock.lock(); defer { lock.unlock() }; if !done { done = true; body() } }
        }
        let once = Once()
        let newBytes = Data("the file kept growing after compression started".utf8)
        let result = await CompressionEngine(destination: out, trashOriginal: true, trash: fakeTrash)
            .compress(source, isDirectory: false) { value in
                guard value > 0 else { return }
                once.run { try? newBytes.write(to: source) }
            }

        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertFalse(result.movedToTrash, "a file that changed mid-compression must not be trashed")
        XCTAssertEqual(try Data(contentsOf: source), newBytes, "the original stays in place")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bin.path).count, 0, "nothing went to the Trash")
        XCTAssertEqual(result.trashNote, "Original kept: it changed while it was being compressed.")
        XCTAssertTrue(result.message?.contains("changed while") ?? false,
                      "the row must warn that the compressed copy is from before the change: \(result.message ?? "nil")")
        XCTAssertNotEqual(originalBytes, newBytes)
    }

    /// Sanity check for the test above: an unchanged file is still trashed.
    func testUnchangedOriginalIsStillTrashed() async throws {
        let source = try dir("in").appendingPathComponent("notes.txt")
        try String(repeating: "compress me ", count: 40_000).write(to: source, atomically: true, encoding: .utf8)
        let result = await CompressionEngine(destination: try dir("out"), trashOriginal: true, trash: fakeTrash)
            .compress(source, isDirectory: false) { _ in }
        XCTAssertTrue(result.movedToTrash, result.trashNote ?? "")
        XCTAssertNil(result.message)
    }

    /// "Compress each file" skips hidden files and symbolic links, so they never
    /// reach the mirror. A folder that still holds them is not empty and must
    /// not be swept into the Trash, or those files would exist nowhere else.
    func testFolderWithUnmirroredHiddenFilesIsNotTrashed() throws {
        let folder = try dir("Project")
        try "secret=1".write(to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "ignored".write(to: folder.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "finder metadata".write(to: folder.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)

        let leftovers = FolderExpansion.leftovers(in: folder)
        XCTAssertEqual(Set(leftovers.map(\.lastPathComponent)), [".env", ".gitignore"],
                       "Finder's .DS_Store is regenerated and may be ignored; real dotfiles may not")
    }

    func testFolderWithOnlyFinderMetadataCountsAsEmpty() throws {
        let folder = try dir("Photos")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Empty sub"), withIntermediateDirectories: true)
        try "x".write(to: folder.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        try "x".write(to: folder.appendingPathComponent("Empty sub/.DS_Store"), atomically: true, encoding: .utf8)
        XCTAssertTrue(FolderExpansion.leftovers(in: folder).isEmpty)
    }

    func testSymbolicLinksCountAsLeftovers() throws {
        let folder = try dir("Links")
        let target = work.appendingPathComponent("elsewhere.txt")
        try "x".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias"), withDestinationURL: target)
        XCTAssertEqual(FolderExpansion.leftovers(in: folder).map(\.lastPathComponent), ["alias"])
    }
}

@MainActor
final class TrashSafetyModelTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("trash-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    func testProjectFolderWithDotfilesSurvivesCompressEachFileWithTrash() async throws {
        let fm = FileManager.default
        let data = work.appendingPathComponent("data"), out = work.appendingPathComponent("out")
        let bin = work.appendingPathComponent("FakeTrash")
        for d in [data, out, bin] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))

        let project = work.appendingPathComponent("Project", isDirectory: true)
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try String(repeating: "readme ", count: 30_000).write(to: project.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        try "API_KEY=do-not-lose-me".write(to: project.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: data,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context, confirmTrash: { true }, trash: { url in
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        })
        model.openWhenDone = false
        model.setTrashOriginals(true)
        model.addFiles([project])
        model.setFolderMode(try XCTUnwrap(model.items.first?.id), .contents)
        model.start()
        while model.phase == .running { try await Task.sleep(nanoseconds: 50_000_000) }

        guard case .done(let result) = model.items[0].state else { return XCTFail("folder not done") }
        XCTAssertEqual(result.message, "1 of 1 file compressed")
        XCTAssertTrue(fm.fileExists(atPath: project.appendingPathComponent(".env").path),
                      ".env was never copied to the mirror, so it must stay where it is")
        XCTAssertFalse(fm.fileExists(atPath: project.appendingPathComponent("README.txt").path),
                       "the mirrored file itself is still trashed")
        XCTAssertEqual(result.trashNote, "1 original moved to the Trash. Folder kept: it still has 1 item that wasn't copied (.env).")
    }
}
