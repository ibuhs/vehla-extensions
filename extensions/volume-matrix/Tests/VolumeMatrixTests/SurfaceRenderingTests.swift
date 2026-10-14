import AppKit
import XCTest
import VehlaDockWidgetSDK
@testable import VolumeMatrix

final class SurfaceRenderingTests: XCTestCase {
    @MainActor
    func testPopupHasUsableSizeBeforeEmbeddingAndRenders() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let model = VolumeMatrixModel()
        model.inventory = VolumeInventory(volumes: [
            DiskVolume(id: "disk3s1", identity: "data", name: "Macintosh HD", filesystem: "APFS", mountPoint: "/", isInternal: true, isMountable: true, isLocked: false, isProtected: true, isSystemHelper: false, physicalDisks: ["disk0"], containerID: "disk3", used: 180_000_000_000, capacity: 500_000_000_000, free: 300_000_000_000),
            DiskVolume(id: "disk4s1", identity: "ssd", name: "Studio SSD", filesystem: "EXFAT", mountPoint: "/Volumes/Studio", isInternal: false, isMountable: true, isLocked: false, isProtected: false, isSystemHelper: false, physicalDisks: ["disk4"], containerID: nil, used: 240_000_000_000, capacity: 1_000_000_000_000, free: 760_000_000_000)
        ], containers: [APFSContainer(id: "disk3", capacity: 500_000_000_000, free: 300_000_000_000, physicalDisks: ["disk0"])])
        model.rates = ["disk0": .init(read: 5_000_000, written: 1_000_000), "disk4": .init(read: 30_000_000, written: 12_000_000)]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("volume-matrix-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .systemTeal,
            primaryTextColor: .white, secondaryTextColor: .lightGray, surfaceColor: .windowBackgroundColor)
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "volume-matrix",
            dataDirectory: directory, theme: theme, invalidationHandler: {}, actionHandler: { _ in })
        model.theme = context.theme
        let controller = VolumeMatrixSurfaceController(surface: .popup, model: model)
        // Vehla can inspect a child view's size before it has constrained it.
        XCTAssertGreaterThanOrEqual(controller.view.frame.width, 560)
        XCTAssertGreaterThanOrEqual(controller.view.frame.height, 660)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let backdrop = PreviewBackdrop(frame: NSRect(x: 0, y: 0, width: 560, height: 660))
        let parent = NSViewController()
        parent.view = backdrop
        parent.addChild(controller)
        backdrop.addSubview(controller.view)
        window.contentViewController = parent
        window.setContentSize(NSSize(width: 560, height: 660))
        defer { window.orderOut(nil); window.contentViewController = nil; model.hide() }
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(controller.view.bounds.size, NSSize(width: 560, height: 660))
        XCTAssertFalse(controller.view.subviews.isEmpty)
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        // A transparent shell alone compresses to a tiny PNG. Content should render.
        XCTAssertGreaterThan(png.count, 5_000)
        if let destination = ProcessInfo.processInfo.environment["MATRIX_RENDER_DIRECTORY"] {
            try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("volume-matrix-popup.png"))
        }
    }
}

@MainActor
private final class PreviewBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        bounds.fill()
    }
}
