import AppKit
import XCTest
import VehlaDockWidgetSDK
@testable import PeripheralMatrix

final class QMKRenderingTests: XCTestCase {
    @MainActor func testQMKTabRendersKeyboardAndDraftControls() async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let model = PeripheralMatrixModel(readRegistry: { [] })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("qmk-render-\(UUID())")
        defer { model.close(); try? FileManager.default.removeItem(at: directory) }
        let theme = VehlaDockWidgetTheme(isDark: true, accentColor: .white, primaryTextColor: .white,
            secondaryTextColor: .lightGray, surfaceColor: .windowBackgroundColor)
        model.configure(.init(packageID: "test", widgetID: "peripheral-matrix", dataDirectory: directory, theme: theme, invalidationHandler: {}, actionHandler: { _ in }))
        model.selectedTab = .qmk
        let device = MockVIAEndpoint()
        model.editor.load(endpoint: device, directory: directory)
        await model.editor.waitForOperation()
        XCTAssertNotNil(model.editor.baseline)
        XCTAssertEqual(device.writes, 0)
        model.editor.selectedLayer = 1; model.editor.selectedKey = 0; model.editor.assign(0x0806)
        let controller = PeripheralMatrixSurfaceController(surface: .popup, model: model)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 760), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let backdrop = QMKBackdrop(frame: NSRect(x: 0, y: 0, width: 680, height: 760))
        let parent = NSViewController(); parent.view = backdrop; parent.addChild(controller); backdrop.addSubview(controller.view)
        window.contentViewController = parent
        defer { window.orderOut(nil); window.contentViewController = nil }
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        if let destination = ProcessInfo.processInfo.environment["MATRIX_RENDER_DIRECTORY"] {
            try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent("peripheral-qmk-tab.png"))
        }
    }
}
@MainActor private final class QMKBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); bounds.fill() }
}
