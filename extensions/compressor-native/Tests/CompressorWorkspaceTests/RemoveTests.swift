import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

final class BatchControlTests: XCTestCase {
    func testStoppingOneRowSkipsOnlyItsJobs() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("control-\(UUID().uuidString)")
        let out = work.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let keep = UUID(), drop = UUID()
        var units: [WorkUnit] = []
        for i in 0..<10 {
            let file = work.appendingPathComponent("f\(i).txt")
            try String(repeating: "abc ", count: 20_000).write(to: file, atomically: true, encoding: .utf8)
            units.append(WorkUnit(owner: i.isMultiple(of: 2) ? keep : drop, source: file, isDirectory: false, destination: out, size: 1))
        }
        let jobs = units
        let control = BatchControl()
        control.stop(drop) // the user removed this row before its jobs started
        final class Box: @unchecked Sendable { let lock = NSLock(); var owners: [UUID] = []
            func add(_ o: UUID) { lock.lock(); owners.append(o); lock.unlock() } }
        let box = Box()
        await BatchRunner.run(jobs, options: EngineOptions(), control: control,
                              progress: { _, _ in }, finished: { i, _ in box.add(jobs[i].owner) })
        XCTAssertEqual(box.owners.count, 5)
        XCTAssertTrue(box.owners.allSatisfy { $0 == keep })
    }
}

@MainActor
final class RemoveTests: XCTestCase {
    private var work: URL!
    private var out: URL!
    private var data: URL!

    override func setUpWithError() throws {
        work = FileManager.default.temporaryDirectory.appendingPathComponent("remove-\(UUID().uuidString)")
        out = work.appendingPathComponent("out"); data = work.appendingPathComponent("data")
        for d in [out!, data!] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: work) }

    private func makeModel() -> CompressorModel {
        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: data,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context)
        model.openWhenDone = false
        return model
    }

    private func textFile(_ name: String) throws -> URL {
        let url = work.appendingPathComponent(name)
        try String(repeating: "\(name) ", count: 30_000).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testRemovingBeforeAndAfterCompressing() async throws {
        let model = makeModel()
        model.addFiles([try textFile("a.txt"), try textFile("b.txt"), try textFile("c.txt")])
        model.remove(model.items[1].id)
        XCTAssertEqual(model.items.map(\.name), ["a.txt", "c.txt"])

        model.start()
        while model.phase == .running { try await Task.sleep(nanoseconds: 50_000_000) }
        model.remove(model.items[0].id)
        XCTAssertEqual(model.items.map(\.name), ["c.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: out.appendingPathComponent("a.txt.zip").path),
                      "removing a finished row keeps its saved files")
        model.remove(model.items[0].id)
        XCTAssertEqual(model.phase, .idle, "an empty list goes back to the drop zone")
    }

    func testRemovingARunningVideoStopsItAndLetsTheRestFinish() async throws {
        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let clip = work.appendingPathComponent("long.mov")
        // Noisy 1080p: the standard encoder needs many seconds for this.
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=1920x1080:r=30",
                                      "-vf", "noise=alls=8:allf=t", "-t", "15", "-c:v", "libx264", "-crf", "8",
                                      "-preset", "ultrafast", clip.path])
        let model = makeModel()
        model.addFiles([clip, try textFile("notes.txt")])
        let videoID = model.items[0].id
        model.start()

        try await Task.sleep(nanoseconds: 1_500_000_000)
        guard case .working = model.items[0].state else { return XCTFail("video should still be encoding") }
        let stopAt = Date()
        model.remove(videoID)
        while model.phase == .running { try await Task.sleep(nanoseconds: 50_000_000) }
        let stopTime = Date().timeIntervalSince(stopAt)

        XCTAssertLessThan(stopTime, 3, "removing should stop the encoder promptly")
        XCTAssertEqual(model.items.map(\.name), ["notes.txt"])
        guard case .done(let result) = model.items[0].state else { return XCTFail("other item should finish") }
        XCTAssertEqual(result.status, .compressed)
        let saved = try FileManager.default.contentsOfDirectory(atPath: out.path)
        XCTAssertFalse(saved.contains { $0.hasPrefix("long") }, "no output or partial file for the removed video: \(saved)")
        XCTAssertEqual(model.overallProgress, 1, accuracy: 0.0001, "the removed row no longer counts")
    }
}
