import AppKit
import XCTest
import VehlaDockWidgetSDK
@testable import LofiDockWidget

final class SurfaceRenderingTests: XCTestCase {
    @MainActor
    func testPopupHasUsableSizeBeforeEmbeddingAndRenders() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let plugin = LofiDockWidgetPlugin()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lofi-render-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .systemTeal,
            primaryTextColor: .white, secondaryTextColor: .lightGray, surfaceColor: .windowBackgroundColor)
        LofiPreferences(sourcePromptShown: true).save(to: directory)
        let context = VehlaDockWidgetContext(packageID: "test", widgetID: "lofi",
            dataDirectory: directory, theme: theme, invalidationHandler: {}, actionHandler: { _ in })
        let controller = try plugin.makeViewController(widgetID: "lofi", surface: .popup, context: context)
        // Vehla can inspect a child view's size before it has constrained it.
        XCTAssertGreaterThanOrEqual(controller.view.frame.width, 420)
        XCTAssertGreaterThanOrEqual(controller.view.frame.height, 720)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let backdrop = PreviewBackdrop(frame: NSRect(x: 0, y: 0, width: 420, height: 720))
        let parent = NSViewController()
        parent.view = backdrop
        parent.addChild(controller)
        backdrop.addSubview(controller.view)
        window.contentViewController = parent
        window.setContentSize(NSSize(width: 420, height: 720))
        defer { window.orderOut(nil); window.contentViewController = nil; plugin.widgetWillClose("lofi") }
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(controller.view.bounds.size, NSSize(width: 420, height: 720))
        XCTAssertFalse(controller.view.subviews.isEmpty)
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        // A transparent shell alone compresses to a tiny PNG. Content should render.
        XCTAssertGreaterThan(png.count, 5_000)
        if let destination = ProcessInfo.processInfo.environment["MATRIX_RENDER_DIRECTORY"] {
            try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("lofi-popup.png"))
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
