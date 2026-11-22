import Foundation

public struct ShellResult: Sendable, Equatable {
    public let status: Int32
    public let output: String
    public var ok: Bool { status == 0 }
}

public enum ShellError: Error, LocalizedError {
    case failed(String, Int32)
    public var errorDescription: String? {
        if case .failed(let what, let code) = self { return "\(what) failed (\(code))" }
        return nil
    }
}

public enum Shell {
    /// Runs a program off the main thread and returns its combined output.
    @discardableResult
    public static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: ShellResult(status: 127, output: "\(error)"))
                    return
                }
                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                continuation.resume(returning: ShellResult(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
}
