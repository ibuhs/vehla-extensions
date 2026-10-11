import XCTest
@testable import CompressorWorkspace

final class EngineTests: XCTestCase {
    private var work: URL!
    private var input: URL!
    private var output: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressor-tests-\(UUID().uuidString)", isDirectory: true)
        input = work.appendingPathComponent("in", isDirectory: true)
        output = work.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: work)
    }

    private func ffmpeg(_ args: [String]) async throws {
        let path = try XCTUnwrap(Tools.find("ffmpeg"), "ffmpeg is required for these tests")
        let result = await runProcess(path, ["-v", "error", "-y"] + args)
        XCTAssertEqual(result.status, 0, result.stderr)
    }

    private func compress(_ url: URL, directory: Bool = false) async -> CompressionResult {
        await CompressionEngine(destination: output).compress(url, isDirectory: directory) { _ in }
    }

    func testClassifiesFiles() {
        XCTAssertEqual(MediaKind.classify(URL(fileURLWithPath: "/a/IMG_1.MOV"), isDirectory: false), .video)
        XCTAssertEqual(MediaKind.classify(URL(fileURLWithPath: "/a/p.JPEG"), isDirectory: false), .jpeg)
        XCTAssertEqual(MediaKind.classify(URL(fileURLWithPath: "/a/x.docx"), isDirectory: false), .skip)
        XCTAssertEqual(MediaKind.classify(URL(fileURLWithPath: "/a/dir"), isDirectory: true), .generic)
        XCTAssertEqual(MediaKind.classify(URL(fileURLWithPath: "/a/notes.txt"), isDirectory: false), .generic)
    }

    func testUniqueURLAvoidsOverwriting() throws {
        let existing = output.appendingPathComponent("a.txt")
        try "x".write(to: existing, atomically: true, encoding: .utf8)
        XCTAssertEqual(CompressionEngine.uniqueURL(in: output, name: "a.txt").lastPathComponent, "a (1).txt")
    }

    func testZipsTextAndKeepsOriginal() async throws {
        let file = input.appendingPathComponent("notes.txt")
        try String(repeating: "lorem ipsum ", count: 50_000).write(to: file, atomically: true, encoding: .utf8)
        let result = await compress(file)
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertEqual(result.outputName, "notes.txt.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("notes.txt").path), "original copy")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("notes.txt.zip").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "source untouched")
    }

    func testFolderIsZipped() async throws {
        let folder = input.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try String(repeating: "abc", count: 100_000).write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let result = await compress(folder, directory: true)
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertEqual(result.outputName, "folder.zip")
    }

    func testDestinationInsideFolderIsRejected() async throws {
        let folder = input.appendingPathComponent("folder", isDirectory: true)
        let inner = folder.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let result = await CompressionEngine(destination: inner).compress(folder, isDirectory: true) { _ in }
        XCTAssertEqual(result.status, .failed)
    }

    func testJPEGIsCompressed() async throws {
        let file = input.appendingPathComponent("photo.jpg")
        try await ffmpeg(["-f", "lavfi", "-i", "mandelbrot=s=2000x1400", "-frames:v", "1", "-q:v", "1", file.path])
        let result = await compress(file)
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertLessThan(result.after, result.before)
        XCTAssertEqual(result.outputName, "photo-compressed.jpg")
    }

    func testTinyPDFIsLeftAlone() async throws {
        let gs = try XCTUnwrap(Tools.find("gs"))
        let file = input.appendingPathComponent("doc.pdf")
        let made = await runProcess(gs, ["-q", "-sDEVICE=pdfwrite", "-dNOPAUSE", "-dBATCH", "-sOutputFile=\(file.path)",
                                         "-c", "/Helvetica findfont 20 scalefont setfont 50 700 moveto (hi) show showpage"])
        XCTAssertEqual(made.status, 0)
        let result = await compress(file)
        XCTAssertEqual(result.status, .alreadyOptimal)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("doc-compressed.pdf").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("doc.pdf").path))
    }

    func testVideoWithAACAudioIsCompressedAndReportsProgress() async throws {
        let file = input.appendingPathComponent("clip.MOV")
        try await ffmpeg(["-f", "lavfi", "-i", "testsrc2=s=1280x720:r=30", "-f", "lavfi", "-i", "sine",
                          "-t", "4", "-c:v", "libx264", "-crf", "12", "-c:a", "aac", file.path])
        final class Counter: @unchecked Sendable { var values: [Double] = []; let lock = NSLock()
            func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() } }
        let seen = Counter()
        let result = await CompressionEngine(destination: output).compress(file, isDirectory: false) { seen.add($0) }
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertEqual(result.outputName, "clip-compressed.mp4")
        XCTAssertFalse(seen.values.isEmpty, "progress should be reported")
        XCTAssertEqual(seen.values.last, 1)
    }

    func testStagingFolderIsCleanedUp() async throws {
        let before = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("vehla-compressor-") }.count
        let file = input.appendingPathComponent("n.txt")
        try String(repeating: "x", count: 100_000).write(to: file, atomically: true, encoding: .utf8)
        _ = await compress(file)
        let after = try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("vehla-compressor-") }.count
        XCTAssertEqual(before, after)
    }
}
