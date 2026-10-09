import AppKit
import Foundation

struct QuickNoteLaunchResult: Equatable, Sendable {
    var opened: Bool
    var message: String
}

enum QuickNoteLauncher {
    static func script(for url: URL) -> String {
        let escaped = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "com.chabomakers.Antinote" to activate
        delay 0.25
        open location "\(escaped)"
        """
    }

    static func open(_ url: URL) async -> QuickNoteLaunchResult {
        let script = script(for: url)
        let scripted = await Task.detached { runAppleScript(script) }.value
        if scripted.opened { return scripted }
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        if opened {
            return QuickNoteLaunchResult(opened: true, message: "")
        }
        return scripted
    }

    /// Sends a URL to Antinote without bringing it forward.
    @MainActor
    @discardableResult
    static func deliverInBackground(_ url: URL) async -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
            return true
        } catch {
            QuickNoteDiagnostics.note("background open failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func runAppleScript(_ script: String) -> QuickNoteLaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return QuickNoteLaunchResult(opened: false, message: error.localizedDescription)
        }
        if process.terminationStatus == 0 {
            return QuickNoteLaunchResult(opened: true, message: "")
        }
        let data = errors.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty {
            return QuickNoteLaunchResult(opened: false, message: detail)
        }
        return QuickNoteLaunchResult(opened: false, message: "Antinote did not open.")
    }
}
