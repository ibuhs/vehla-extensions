import Foundation
import os

/// Writes save and create diagnostics to `diagnostics.log` in the widget's
/// storage folder and to the unified log (subsystem com.wiseman.vehla.antinote).
@MainActor
enum QuickNoteDiagnostics {
    static var directory: URL?
    private static let logger = Logger(subsystem: "com.wiseman.vehla.antinote", category: "widget")
    private static let stamp = ISO8601DateFormatter()

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("diagnostics.log")
        let line = Data("\(stamp.string(from: Date())) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
