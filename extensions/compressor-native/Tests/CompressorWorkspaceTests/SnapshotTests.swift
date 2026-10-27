import AppKit
import SwiftUI
import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

/// Renders the window to PNGs for visual review. Runs only when SNAPSHOT_DIR is set.
@MainActor
final class SnapshotTests: XCTestCase {
    private func theme(dark: Bool) -> VehlaWorkspaceTheme {
        VehlaWorkspaceTheme(
            isDark: dark,
            accentColor: .systemBlue,
            primaryTextColor: dark ? .white : .black,
            secondaryTextColor: dark ? NSColor(white: 1, alpha: 0.6) : NSColor(white: 0, alpha: 0.55),
            surfaceColor: dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1),
            backgroundColor: dark ? NSColor(white: 0.09, alpha: 1) : NSColor(white: 0.93, alpha: 1)
        )
    }

    /// Stand-in for Vehla's translucent panel, so plain glass has something to refract.
    private var panelStandIn: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.62, green: 0.40, blue: 0.50), Color(red: 0.25, green: 0.45, blue: 0.50),
                                    Color(red: 0.20, green: 0.25, blue: 0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.85, green: 0.55, blue: 0.65).opacity(0.7)).frame(width: 280).blur(radius: 70).offset(x: -150, y: -220)
            Circle().fill(Color(red: 0.25, green: 0.75, blue: 0.75).opacity(0.6)).frame(width: 300).blur(radius: 80).offset(x: 200, y: 60)
        }.ignoresSafeArea()
    }

    private func render(_ model: CompressorModel, theme: VehlaWorkspaceTheme, to path: String) throws {
        let box = ThemeBox(theme: theme)
        let view = CompressorWorkspaceView(model: model, themeBox: box)
        let host = NSHostingView(rootView: ZStack {
            if !model.tinted { panelStandIn }
            view
        })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 780),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.setFrameOrigin(NSPoint(x: 200, y: 120))
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
        try capture.run()
        capture.waitUntilExit()
        window.close()
    }

    func testSnapshots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { throw XCTSkip("SNAPSHOT_DIR not set") }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("snap-\(UUID().uuidString)")
        let data = work.appendingPathComponent("data"), out = work.appendingPathComponent("Compressed")
        let inp = work.appendingPathComponent("in")
        for d in [data, out, inp] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try JSONSerialization.data(withJSONObject: ["destination": out.path]).write(to: data.appendingPathComponent("state.json"))

        let ff = try XCTUnwrap(Tools.find("ffmpeg"))
        _ = await runProcess(ff, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=2400x1600", "-frames:v", "1", "-q:v", "1", inp.appendingPathComponent("Holiday photo.jpg").path])
        _ = await runProcess(ff, ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=s=1280x720:r=30", "-t", "3", "-c:v", "libx264", "-crf", "12", inp.appendingPathComponent("IMG_2581.MOV").path])
        try String(repeating: "lorem ipsum ", count: 80_000).write(to: inp.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)

        let context = VehlaWorkspaceContext(
            packageID: "x", workspaceID: "compressor", dataDirectory: data,
            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme(dark: true),
            secretLookup: { _ in nil }, actionHandler: { _ in }
        )
        let model = CompressorModel(context: context)
        model.openWhenDone = false
        model.setTinted(true)

        try render(model, theme: theme(dark: true), to: "\(dir)/1-empty-dark.png")
        model.addFiles(["Holiday photo.jpg", "IMG_2581.MOV", "Notes.txt"].map { inp.appendingPathComponent($0) })
        try render(model, theme: theme(dark: true), to: "\(dir)/2-queued-dark.png")
        model.start()
        while model.phase == .running { try await Task.sleep(nanoseconds: 100_000_000) }
        try render(model, theme: theme(dark: true), to: "\(dir)/3-done-dark.png")
        try render(model, theme: theme(dark: false), to: "\(dir)/4-done-light.png")

        // Plain system Liquid Glass (the default style).
        model.setTinted(false)
        try render(model, theme: theme(dark: true), to: "\(dir)/5-plain-done-dark.png")
        model.newBatch()
        try render(model, theme: theme(dark: true), to: "\(dir)/6-plain-empty-dark.png")
        model.setTinted(true)
        try render(model, theme: theme(dark: true), to: "\(dir)/7-tinted-empty-dark.png")

        // Free-space warning: a 50 TB sparse file (uses no real disk) must be refused.
        model.setTinted(false)
        let huge = inp.appendingPathComponent("Huge archive.mov")
        fm.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: 50 * 1_000_000_000_000)
        try handle.close()
        model.addFiles([inp.appendingPathComponent("Holiday photo.jpg"), huge])
        model.setQuality(.best)
        model.start()
        XCTAssertNotNil(model.notice)
        XCTAssertEqual(model.phase, .idle, "a refused batch must not start")
        try render(model, theme: theme(dark: true), to: "\(dir)/8-notice-dark.png")

        // Missing-tools banner (Homebrew present) and the Homebrew-missing variant.
        let missingTools: Set<String> = ["ffmpeg", "ffprobe", "gs", "cwebp"]
        let bare = CompressorModel(context: context, toolFinder: { missingTools.contains($0) ? nil : Tools.find($0) })
        try render(bare, theme: theme(dark: true), to: "\(dir)/9-missing-tools-dark.png")
        let noBrew = CompressorModel(context: context, toolFinder: { (missingTools.union(["brew"])).contains($0) ? nil : Tools.find($0) })
        try render(noBrew, theme: theme(dark: true), to: "\(dir)/10-no-homebrew-dark.png")
        let tip = CompressorModel(context: context, toolFinder: { $0 == "oxipng" ? nil : Tools.find($0) })
        try render(tip, theme: theme(dark: true), to: "\(dir)/11-optional-tip-dark.png")

        // New in 1.4: folder modes, options, and the animated progress bars mid-run.
        let album = inp.appendingPathComponent("Summer album", isDirectory: true)
        try fm.createDirectory(at: album, withIntermediateDirectories: true)
        for i in 0..<6 {
            _ = await runProcess(ff, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=2400x1600:start_scale=\(3 + Double(i) * 0.2)",
                                      "-frames:v", "1", "-q:v", "1", album.appendingPathComponent("IMG_\(100 + i).jpg").path])
        }
        let longClip = inp.appendingPathComponent("Beach day.mov")
        _ = await runProcess(ff, ["-v", "error", "-y", "-f", "lavfi", "-i", "mandelbrot=s=1920x1080:r=30", "-vf", "noise=alls=6:allf=t",
                                  "-t", "8", "-c:v", "libx264", "-crf", "10", "-preset", "ultrafast", longClip.path])
        let live = CompressorModel(context: context, toolFinder: { Tools.find($0) })
        live.openWhenDone = false
        live.setTinted(false)
        live.setQuality(.balanced)
        live.setFastVideo(false)
        live.addFiles([album, longClip, inp.appendingPathComponent("Notes.txt")])
        live.setFolderMode(try XCTUnwrap(live.items.first?.id), .contents)
        try render(live, theme: theme(dark: true), to: "\(dir)/12-folder-options-dark.png")
        live.start()
        try await Task.sleep(nanoseconds: 2_500_000_000)
        try render(live, theme: theme(dark: true), to: "\(dir)/13-running-dark.png")
        try render(live, theme: theme(dark: false), to: "\(dir)/14-running-light.png")
        while live.phase == .running { try await Task.sleep(nanoseconds: 100_000_000) }
        try render(live, theme: theme(dark: true), to: "\(dir)/15-done-dark.png")
        try? fm.removeItem(at: work)
    }
}
