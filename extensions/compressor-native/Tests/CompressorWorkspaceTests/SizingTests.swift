import AppKit
import SwiftUI
import XCTest
import VehlaNativeUISDK
@testable import CompressorWorkspace

/// The view must never ask for more width than Vehla's window gives it.
@MainActor
final class SizingTests: XCTestCase {
    func testViewFitsMinimumWindowWidth() throws {
        let theme = VehlaWorkspaceTheme(isDark: true, accentColor: .systemBlue, primaryTextColor: .white,
                                        secondaryTextColor: .gray, surfaceColor: .darkGray, backgroundColor: .black)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sizing-\(UUID().uuidString)")
        let long = work.appendingPathComponent("A/very/long/destination/folder/name/that/goes/on/and/on/forever/and/ever")
        try FileManager.default.createDirectory(at: long, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["destination": long.path])
            .write(to: work.appendingPathComponent("state.json"))
        let file = work.appendingPathComponent("An extremely long file name that keeps going and going and going for ages.mov")
        try Data(count: 10).write(to: file)

        let context = VehlaWorkspaceContext(
            packageID: "x", workspaceID: "compressor", dataDirectory: work,
            launchRequest: VehlaWorkspaceLaunchRequest(), theme: theme,
            secretLookup: { _ in nil }, actionHandler: { _ in })
        let model = CompressorModel(context: context)
        let host = NSHostingView(rootView: CompressorWorkspaceView(model: model, themeBox: ThemeBox(theme: theme)))

        for label in ["empty", "queued"] {
            if label == "queued" { model.addFiles([file]) }
            let width = host.fittingSize.width
            print("FITTING \(label): \(width)")
            XCTAssertLessThanOrEqual(width, 560, "\(label) state is wider than the minimum window")
        }
        try? FileManager.default.removeItem(at: work)
    }
}
