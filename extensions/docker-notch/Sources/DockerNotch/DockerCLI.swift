import Foundation

/// Runs the user's own `docker` command. Everything here is off the main thread.
enum DockerCLI {
    struct Output: Sendable {
        var status: Int32
        var text: String
    }

    /// Where Docker Desktop, Homebrew, OrbStack and Colima setups put the command. An app's PATH has none of them.
    static let candidates: [String] = {
        let home = NSHomeDirectory()
        return ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", home + "/.docker/bin/docker", home + "/.orbstack/bin/docker",
                "/Applications/Docker.app/Contents/Resources/bin/docker", home + "/.rd/bin/docker"]
    }()

    static func path() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The command's folder goes on PATH so Docker finds its own helpers (credential stores, plugins).
    static func environment(for path: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let folders = [(path as NSString).deletingLastPathComponent, "/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (folders + [environment["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        return environment
    }

    /// Nil when Docker isn't installed. A command still running after `timeout` is ended.
    static func run(_ arguments: [String], timeout: TimeInterval = 15) async -> Output? {
        guard let path = path() else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = environment(for: path)
                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice
                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: stop)
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stop.cancel()
                continuation.resume(returning: Output(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self)))
            }
        }
    }
}

/// One long-lived `docker events` process: Docker says when a container starts or stops, so nothing polls.
final class DockerEventStream: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var buffer = Data()

    /// False when Docker isn't installed or the command couldn't start. `onEnd` runs when the stream ends by
    /// itself (Docker quit), never after `stop()`.
    func start(onEvent: @escaping @Sendable (DockerEvent) -> Void, onEnd: @escaping @Sendable () -> Void) -> Bool {
        guard let path = DockerCLI.path() else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["events", "--filter", "type=container", "--format", "{{json .}}"]
        process.environment = DockerCLI.environment(for: path)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            for line in self.lines(adding: data) {
                if let event = DockerParser.event(line) { onEvent(event) }
            }
        }
        process.terminationHandler = { [weak self] ended in
            output.fileHandleForReading.readabilityHandler = nil
            guard let self else { return }
            let wasCurrent = self.lock.withLock { () -> Bool in
                guard self.process === ended else { return false }
                self.process = nil
                return true
            }
            if wasCurrent { onEnd() }
        }
        do { try process.run() } catch { return false }
        lock.withLock { self.process = process }
        return true
    }

    func stop() {
        let running = lock.withLock { () -> Process? in
            defer { process = nil }
            return process
        }
        if running?.isRunning == true { running?.terminate() }
    }

    var isRunning: Bool { lock.withLock { process != nil } }

    private func lines(adding data: Data) -> [String] {
        lock.withLock {
            buffer.append(data)
            var lines: [String] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            // A line that never ends isn't an event.
            if buffer.count > 1_000_000 { buffer.removeAll() }
            return lines
        }
    }
}
