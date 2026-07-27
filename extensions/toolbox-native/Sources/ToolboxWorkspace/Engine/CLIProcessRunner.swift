import Foundation

/// Runs local CLI tools off the main thread.
actor CLIProcessRunner {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    func run(
        executable: String,
        arguments: [String],
        stdin: String? = nil,
        environment: [String: String] = [:],
        timeoutSeconds: TimeInterval = 20
    ) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            try Self.runSync(
                executable: executable,
                arguments: arguments,
                stdin: stdin,
                environment: environment,
                timeoutSeconds: timeoutSeconds
            )
        }.value
    }

    func which(_ name: String) async -> String? {
        let result = try? await run(executable: "/usr/bin/which", arguments: [name])
        let path = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (path?.isEmpty == false) ? path : nil
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        stdin: String?,
        environment: [String: String],
        timeoutSeconds: TimeInterval
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env

        let out = Pipe()
        let err = Pipe()
        let input = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input

        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(Data(stdin.utf8))
        }
        try? input.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw ToolError.failed("Command timed out after \(Int(timeoutSeconds))s: \(executable)")
        }
        process.waitUntilExit()

        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
