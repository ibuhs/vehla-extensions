import AppKit
import SwiftUI
import XCTest
@testable import PeripheralMatrix

final class BridgeSetupTests: XCTestCase {
    @MainActor func testSetupAssistantLoadsOfflineResourcesAndRenders() async throws {
        _ = NSApplication.shared
        XCTAssertGreaterThan(try XCTUnwrap(QMKBridgeSetupContent.guide).count, 1_000)
        XCTAssertGreaterThan(try XCTUnwrap(QMKBridgeSetupContent.prompt).count, 2_000)
        let controller = NSHostingController(rootView: QMKBridgeSetupView().environment(\.colorScheme, .dark))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let backdrop = BridgeSetupBackdrop(frame: NSRect(x: 0, y: 0, width: 620, height: 680))
        let parent = NSViewController(); parent.view = backdrop
        parent.addChild(controller); backdrop.addSubview(controller.view)
        controller.view.frame = backdrop.bounds
        window.contentViewController = parent
        defer { window.orderOut(nil); window.contentViewController = nil }
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let bitmap = try XCTUnwrap(backdrop.bitmapImageRepForCachingDisplay(in: backdrop.bounds))
        backdrop.cacheDisplay(in: backdrop.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        if let directory = ProcessInfo.processInfo.environment["MATRIX_RENDER_DIRECTORY"] {
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("qmk-bridge-setup.png"))
        }
    }
}

@MainActor private final class BridgeSetupBackdrop: NSView {
    override func draw(_ dirtyRect: NSRect) { NSColor(calibratedWhite: 0.16, alpha: 1).setFill(); bounds.fill() }
}
