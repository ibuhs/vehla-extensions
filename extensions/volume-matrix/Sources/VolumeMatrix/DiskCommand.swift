import Foundation

/// Fixed executable and argument arrays, bounded execution, off the UI thread.
/// File-backed output avoids pipe backpressure on large inventories.
enum DiskCommand {
    static func run(_ arguments: [String], timeout: TimeInterval = 10) throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vehla-volume-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            process.terminate()
            throw DiskError.message("Disk scan timed out. Try refreshing.")
        }
        let data = try Data(contentsOf: output)
        guard process.terminationStatus == 0 else {
            throw DiskError.message("macOS could not read disk information. Try refreshing or open Disk Utility.")
        }
        return data
    }
}
enum DiskError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
