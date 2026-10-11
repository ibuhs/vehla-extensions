import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

/// While a batch runs, macOS must show a "prevent idle sleep" assertion from us.
@MainActor
final class KeepAwakeTests: XCTestCase {
    private func assertions() async -> String {
        await runProcess("/usr/bin/pmset", ["-g", "assertions"]).stdout
    }

    func testSleepIsPreventedOnlyWhileCompressing() async throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("awake-\(UUID().uuidString)")
        let data = work.appendingPathComponent("data"), out = work.appendingPathComponent("out"), inp = work.appendingPathComponent("in")
        for d in [data, out, inp] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: work) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))

        let ffmpeg = try XCTUnwrap(Tools.find("ffmpeg"))
        let clip = inp.appendingPathComponent("clip.mp4")
        _ = await runProcess(ffmpeg, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=1920x1080:r=30",
                                      "-t", "8", "-c:v", "libx264", "-crf", "10", clip.path])

        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let context = VehlaWorkspaceContext(packageID: "x", workspaceID: "compressor", dataDirectory: data,
                                            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
                                            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context)
        model.openWhenDone = false
        model.addFiles([clip])

        let before = await assertions()
        XCTAssertFalse(before.contains("Compressing files"), "no assertion before the batch starts")

        model.start()
        var sawAssertion = false
        while model.phase == .running {
            if await assertions().contains("Compressing files") { sawAssertion = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        XCTAssertTrue(sawAssertion, "macOS should show our sleep-prevention assertion while compressing")

        while model.phase == .running { try await Task.sleep(nanoseconds: 200_000_000) }
        let after = await assertions()
        XCTAssertFalse(after.contains("Compressing files"), "assertion must be released when the batch ends")
    }
}
