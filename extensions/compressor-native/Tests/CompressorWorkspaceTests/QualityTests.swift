import XCTest
@testable import CompressorWorkspace

final class QualityTests: XCTestCase {
    private var work: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("quality-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    func testPresetsAreOrderedFromSmallerToBest() {
        XCTAssertGreaterThan(QualityPreset.smaller.videoCRF, QualityPreset.balanced.videoCRF)
        XCTAssertGreaterThan(QualityPreset.balanced.videoCRF, QualityPreset.best.videoCRF)
        XCTAssertLessThan(QualityPreset.smaller.jpegQuality, QualityPreset.balanced.jpegQuality)
        XCTAssertLessThan(QualityPreset.balanced.jpegQuality, QualityPreset.best.jpegQuality)
        XCTAssertEqual(QualityPreset.balanced.videoCRF, 24, "balanced must stay the previous default")
        XCTAssertEqual(QualityPreset.balanced.jpegQuality, 85)
        XCTAssertEqual(QualityPreset.balanced.pdfSettings, "/printer")
    }

    func testJPEGSizeFollowsThePreset() async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let photo = work.appendingPathComponent("photo.jpg")
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=2000x1400",
                                      "-frames:v", "1", "-q:v", "1", photo.path])
        var sizes: [QualityPreset: Int64] = [:]
        for preset in QualityPreset.allCases {
            let out = work.appendingPathComponent("out-\(preset.rawValue)", isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let result = await CompressionEngine(destination: out, quality: preset).compress(photo, isDirectory: false) { _ in }
            XCTAssertEqual(result.status, .compressed, "\(preset): \(result.message ?? "")")
            sizes[preset] = result.after
        }
        let smaller = try XCTUnwrap(sizes[.smaller]), balanced = try XCTUnwrap(sizes[.balanced]), best = try XCTUnwrap(sizes[.best])
        XCTAssertLessThan(smaller, balanced)
        XCTAssertLessThan(balanced, best)
    }

    func testVideoSizeFollowsThePreset() async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let clip = work.appendingPathComponent("clip.mp4")
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=1280x720:r=30",
                                      "-t", "3", "-c:v", "libx264", "-crf", "10", clip.path])
        var sizes: [Int64] = []
        for preset in [QualityPreset.smaller, .best] {
            let out = work.appendingPathComponent("v-\(preset.rawValue)", isDirectory: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let result = await CompressionEngine(destination: out, quality: preset).compress(clip, isDirectory: false) { _ in }
            XCTAssertEqual(result.status, .compressed, result.message ?? "")
            sizes.append(result.after)
        }
        XCTAssertLessThan(sizes[0], sizes[1], "Smaller preset should give a smaller video than Best")
    }

    // MARK: Free space

    func testPreflightPassesForSmallBatches() {
        XCTAssertNil(Preflight.check(sizes: [1_000_000, 5_000_000], destination: work))
        XCTAssertNil(Preflight.check(sizes: [], destination: work))
    }

    func testPreflightRefusesBatchesLargerThanTheDisk() throws {
        let message = try XCTUnwrap(Preflight.check(sizes: [Int64(50) * 1_000_000_000_000], destination: work))
        XCTAssertTrue(message.contains("Not enough"), message)
    }

    func testPreflightCountsTheWholeBatchForTheDestination() throws {
        let values = try work.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = try XCTUnwrap(values.volumeAvailableCapacityForImportantUsage)
        // Destination and temp share a disk here: one file needs ~4.2x its size in total, three need ~7.4x.
        let each = Int64(Double(free) * 0.2)
        XCTAssertNil(Preflight.check(sizes: [each], destination: work))
        XCTAssertNotNil(Preflight.check(sizes: [each, each, each], destination: work))
    }
}
