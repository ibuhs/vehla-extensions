import ImageIO
import UniformTypeIdentifiers
import VehlaNativeUISDK
import XCTest
@testable import CompressorWorkspace

/// Items dragged in from Photos and other apps, and the engine's handling of
/// files that are empty or that a tool can't read.
final class DropImportTests: XCTestCase {
    private var work: URL!
    private var imports: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("drops-\(UUID().uuidString)", isDirectory: true)
        imports = work.appendingPathComponent("data/Imports", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        CompressionEngine.resetNameReservations()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func dir(_ name: String) throws -> URL {
        let url = work.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func photo(at url: URL) async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let out = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=1600x1200",
                                            "-frames:v", "1", "-q:v", "1", url.path])
        XCTAssertEqual(out.status, 0, out.stderr)
    }

    /// A provider shaped like a Photos drag: JPEG content only, no file link,
    /// and a machine-generated name.
    private func photosStyleProvider(serving file: URL, writeDelay: TimeInterval = 0) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = "uuid=9C495A65-DE1B-4AF8-AF58-B3BF2055A4CB&code=001&library=1&type=1&mode=1"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { done in
            if writeDelay == 0 {
                done(file, false, nil)
            } else {
                // A slow sender: the content only exists once it has finished writing.
                DispatchQueue.global().asyncAfter(deadline: .now() + writeDelay) { done(file, false, nil) }
            }
            return nil
        }
        return provider
    }

    private func receive(_ provider: NSItemProvider) async -> Result<DropImporter.Received, DropImporter.Failure> {
        await withCheckedContinuation { continuation in
            DropImporter.receive(provider, into: imports) { continuation.resume(returning: $0) }
        }
    }

    private func size(_ url: URL) -> Int64 { CompressionEngine.size(of: url) }

    // MARK: The bug as it happened

    /// What 1.4.2 did: keep the address macOS hands over for dropped content.
    /// The file is only valid while the drop is being handled.
    func testDroppedContentDisappearsIfOnlyItsAddressIsKept() async throws {
        let source = try dir("photos").appendingPathComponent("IMG_0001.jpeg")
        try await photo(at: source)
        let provider = photosStyleProvider(serving: source)

        let kept: URL? = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier) { url, _ in
                continuation.resume(returning: url)
            }
        }
        let address = try XCTUnwrap(kept)
        XCTAssertTrue(DropImporter.isVolatile(address), "macOS hands over a temporary copy: \(address.path)")
        try await Task.sleep(nanoseconds: 500_000_000) // the user pressing Compress a moment later
        XCTAssertEqual(size(address), 0, "by then the temporary file is gone or empty, which is what the user hit")
    }

    func testPhotosStyleDropIsCopiedBeforeMacOSCleansUp() async throws {
        let source = try dir("photos").appendingPathComponent("IMG_0001.jpeg")
        try await photo(at: source)

        let received = try await receive(photosStyleProvider(serving: source)).get()
        XCTAssertTrue(received.imported)
        XCTAssertTrue(CompressionEngine.isInside(received.url, imports), "kept in Compressor's own storage")
        XCTAssertFalse(received.url.lastPathComponent.hasPrefix("uuid="), "no machine names in the list or the destination")
        XCTAssertEqual(received.url.pathExtension, "jpeg")

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(size(received.url), size(source), "still the full file when Compress is pressed")
    }

    func testSlowSenderIsWaitedForInsteadOfCopyingAnEmptyFile() async throws {
        let source = try dir("photos").appendingPathComponent("IMG_0002.jpeg")
        try await photo(at: source)
        let received = try await receive(photosStyleProvider(serving: source, writeDelay: 0.6)).get()
        XCTAssertEqual(size(received.url), size(source))
    }

    // MARK: Files that should stay where they are

    func testFinderFileIsUsedInPlace() throws {
        // Finder drops are links to the user's own files, outside temporary storage.
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = caches.appendingPathComponent("compressor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Notes.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: file))

        let expectation = expectation(description: "received")
        nonisolated(unsafe) var outcome: Result<DropImporter.Received, DropImporter.Failure>?
        DropImporter.receive(provider, into: imports) { outcome = $0; expectation.fulfill() }
        wait(for: [expectation], timeout: 10)

        let received = try XCTUnwrap(outcome).get()
        XCTAssertFalse(received.imported, "a real file is never copied")
        XCTAssertEqual(received.url.standardizedFileURL.resolvingSymlinksInPath(), file.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: imports.path))
    }

    func testFileLinkIntoTemporaryStorageIsStillCopied() async throws {
        let temp = try dir("TemporaryItems/NSIRD_Photos_abc").appendingPathComponent("IMG_0003.jpeg")
        try await photo(at: temp)
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: temp))
        let received = try await receive(provider).get()
        XCTAssertTrue(received.imported)
        XCTAssertEqual(received.url.lastPathComponent, "IMG_0003.jpeg", "a human name is kept")
        XCTAssertEqual(size(received.url), size(temp))
    }

    func testEmptyDropIsRefusedWithAClearMessage() async throws {
        let empty = try dir("photos").appendingPathComponent("blank.jpeg")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        guard case .failure(let failure) = await receive(photosStyleProvider(serving: empty)) else {
            return XCTFail("an empty drop must not be added")
        }
        XCTAssertEqual(failure.message, "The dropped file was empty. Try dragging it in again.")
    }

    // MARK: Names

    func testNames() {
        let jpeg = URL(fileURLWithPath: "/tmp/x/uuid=9C49&code=001&library=1.jpeg")
        XCTAssertEqual(DropImporter.fileName(for: jpeg, suggestedName: "IMG_2581", type: .jpeg), "IMG_2581.jpeg")
        XCTAssertEqual(DropImporter.fileName(for: jpeg, suggestedName: "Beach.JPEG", type: .jpeg), "Beach.JPEG")
        let fallback = DropImporter.fileName(for: jpeg, suggestedName: "uuid=9C49&code=001", type: .jpeg)
        XCTAssertFalse(fallback.contains("uuid="), fallback)
        XCTAssertEqual((fallback as NSString).pathExtension, "jpeg")
        XCTAssertEqual(DropImporter.fileName(for: URL(fileURLWithPath: "/tmp/x/Holiday.png"), suggestedName: nil, type: .png), "Holiday.png")
    }

    func testNamelessPhotoIsNamedAfterWhenItWasTaken() throws {
        // A JPEG carrying EXIF DateTimeOriginal, as a camera or iPhone writes it.
        let file = try dir("drop").appendingPathComponent("uuid=9C49&code=001&library=1.jpeg")
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: "2024:07:14 18:42:05",
        ]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        XCTAssertEqual(DropImporter.fileName(for: file, suggestedName: "uuid=9C49&code=001", type: .jpeg),
                       "Photo 2024-07-14 at 18.42.05.jpeg")
    }

    func testNamelessVideoIsNamedAfterWhenItWasTaken() async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let file = try dir("drop").appendingPathComponent("uuid=DA56&code=001.mov")
        // The iPhone's own tag, which keeps the local time zone it was shot in.
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=320x240:r=30", "-t", "1",
                                      "-c:v", "libx264", "-movflags", "use_metadata_tags",
                                      "-metadata", "com.apple.quicktime.creationdate=2024-07-14T18:42:05-0400", file.path])
        let name = DropImporter.fileName(for: file, suggestedName: nil, type: .quickTimeMovie)
        let expected = DateFormatter()
        expected.locale = Locale(identifier: "en_US_POSIX")
        expected.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let taken = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-07-14T18:42:05-04:00"))
        XCTAssertEqual(name, "Video \(expected.string(from: taken)).mov")
    }

    func testPhotoWithoutACaptureDateUsesTheDropTime() throws {
        let file = try dir("drop").appendingPathComponent("uuid=02C9&code=001.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        let name = DropImporter.fileName(for: file, suggestedName: nil, type: .png)
        XCTAssertTrue(name.hasPrefix("Photo \(stamp.string(from: Date()))"), name)
        XCTAssertTrue(name.hasSuffix(".png"), name)
    }

    // MARK: The engine's safety net

    func testEmptyFileIsAnErrorAndNothingIsSaved() async throws {
        let empty = try dir("in").appendingPathComponent("uuid=ABC&code=001.jpeg")
        FileManager.default.createFile(atPath: empty.path, contents: Data())
        let out = try dir("out")
        let result = await CompressionEngine(destination: out).compress(empty, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message?.contains("empty (0 bytes)") ?? false, result.message ?? "nil")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [], "no empty 'original' in the destination")
    }

    func testToolThatSilentlySkipsAFileIsAFailure() async throws {
        // sips exits 0 and writes nothing when handed a folder with an image
        // name, the layout Photos uses for some drops ("uuid=…png/IMG.png").
        let wrapper = try dir("in/uuid=8AABF1A0&code=001.jpeg")
        try await photo(at: wrapper.appendingPathComponent("IMG_0005.jpeg"))
        let out = try dir("out")
        let result = await CompressionEngine(destination: out).compress(wrapper, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .failed, "must not report 'Already well optimised'")
        XCTAssertTrue(result.message?.hasPrefix("sips couldn't read this file") ?? false, result.message ?? "nil")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [], "nothing copied to the destination")
    }

    func testCorruptFileFailsWithACleanMessage() async throws {
        let corrupt = try dir("in").appendingPathComponent("broken.jpeg")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: corrupt)
        let out = try dir("out")
        let result = await CompressionEngine(destination: out).compress(corrupt, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message?.hasPrefix("sips failed") ?? false, result.message ?? "nil")
        XCTAssertFalse(result.message?.contains("/var/folders") ?? true, "no temporary paths in the message")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), [])
    }

    func testOxipngErrorNamesTheFileNotItsTemporaryCopy() async throws {
        let png = try dir("in").appendingPathComponent("uuid=8AABF1A0&code=001.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0]).write(to: png) // a PNG header, then nothing
        let result = await CompressionEngine(destination: try dir("out")).compress(png, isDirectory: false) { _ in }
        XCTAssertEqual(result.status, .failed)
        XCTAssertFalse(result.message?.contains("/var/folders") ?? true, result.message ?? "nil")
        XCTAssertFalse(result.message?.contains("vehla-compressor-") ?? true, result.message ?? "nil")
    }
}

/// The whole flow through the window: drop from Photos, compress with
/// "Move originals to Trash" on.
@MainActor
final class DropImportModelTests: XCTestCase {
    func testPhotosDropCompressesAndNothingGoesToTheTrash() async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("drop-model-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: work) }
        let data = work.appendingPathComponent("data"), out = work.appendingPathComponent("out")
        for d in [data, out] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))

        let source = work.appendingPathComponent("IMG_0004.jpeg")
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=1600x1200",
                                      "-frames:v", "1", "-q:v", "1", source.path])
        let provider = NSItemProvider()
        provider.suggestedName = "uuid=02C9D56C-6F34-4597-9980-FF46B3F6447E&code=001&library=1"
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { done in
            done(source, false, nil); return nil
        }

        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: data,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context, confirmTrash: { true },
                                    trash: { url in XCTFail("Compressor's own copy must never go to the Trash: \(url.path)") })
        model.openWhenDone = false
        model.setTrashOriginals(true)

        model.receive([provider])
        for _ in 0..<100 where model.items.isEmpty { try await Task.sleep(nanoseconds: 50_000_000) }
        let item = try XCTUnwrap(model.items.first)
        XCTAssertTrue(item.isImported)
        XCTAssertEqual(item.typeLabel, "Image · copied from another app")

        try await Task.sleep(nanoseconds: 500_000_000) // well after macOS would have cleaned the drop up
        model.start()
        while model.phase == .running { try await Task.sleep(nanoseconds: 50_000_000) }

        guard case .done(let result) = model.items[0].state else { return XCTFail("not done") }
        XCTAssertEqual(result.status, .compressed, result.message ?? "")
        XCTAssertFalse(result.movedToTrash)
        let saved = try fm.contentsOfDirectory(atPath: out.path).sorted()
        XCTAssertEqual(saved.count, 2, "original copy + compressed: \(saved)")
        XCTAssertFalse(saved.contains { $0.hasPrefix("uuid=") }, "human names in the destination: \(saved)")
        for name in saved {
            XCTAssertGreaterThan(CompressionEngine.size(of: out.appendingPathComponent(name)), 0, "\(name) must not be empty")
        }
        let original = try XCTUnwrap(saved.first { !$0.contains("-compressed") })
        XCTAssertTrue(fm.contentsEqual(atPath: out.appendingPathComponent(original).path, andPath: source.path),
                      "the saved original is byte-identical to what was dropped")
        XCTAssertFalse(fm.fileExists(atPath: item.url.path), "Compressor's copy is cleaned up once it's done")
    }
}
