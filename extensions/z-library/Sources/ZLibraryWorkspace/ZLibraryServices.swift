import Foundation

actor ZLibraryCLI {
    static let shared = ZLibraryCLI()

    func isAvailable(settings: ZLibrarySettings) -> Bool {
        (try? run(arguments: ["version"], settings: settings)) != nil
    }

    func search(_ query: String, settings: ZLibrarySettings) async throws -> [ZLibraryBook] {
        let output = try run(
            arguments: ["search", query, "--json", "--count", "30"],
            settings: settings
        )
        guard let data = output.data(using: .utf8),
              let response = try? JSONDecoder().decode(ZLibrarySearchResponse.self, from: data) else {
            throw ZLibraryError.invalidSearchResponse
        }
        return response.books
    }

    func download(_ book: ZLibraryBook, settings: ZLibrarySettings) async throws {
        let directory = NSString(string: settings.downloadDirectory).expandingTildeInPath
        _ = try run(
            arguments: ["download", book.id, "--dir", directory],
            settings: settings
        )
    }

    static func candidatePaths(
        configuredPath: String,
        environment: [String: String],
        homeDirectory: String
    ) -> [String] {
        let configured = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            if configured.contains("/") {
                return [NSString(string: configured).expandingTildeInPath]
            }
            return pathCandidates(named: configured, environment: environment)
        }

        return [
            "/opt/homebrew/bin/zlib",
            "/usr/local/bin/zlib",
            "\(homeDirectory)/.local/bin/zlib",
        ] + pathCandidates(named: "zlib", environment: environment)
    }

    private static func pathCandidates(
        named executable: String,
        environment: [String: String]
    ) -> [String] {
        (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(executable).path }
    }

    private func executableCandidates(settings: ZLibrarySettings) -> [String] {
        let manager = FileManager.default
        return Self.candidatePaths(
            configuredPath: settings.binaryPath,
            environment: ProcessInfo.processInfo.environment,
            homeDirectory: manager.homeDirectoryForCurrentUser.path
        )
    }

    private func run(
        arguments: [String],
        settings: ZLibrarySettings
    ) throws -> String {
        var environment = ProcessInfo.processInfo.environment
        let domain = settings.domainOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty {
            environment["ZLIB_DOMAIN"] = domain
        }

        for executable in executableCandidates(settings: settings) {
            let process = Process()
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vehla-zlib-\(UUID().uuidString).stdout")
            let errorURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("vehla-zlib-\(UUID().uuidString).stderr")
            _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            guard let output = try? FileHandle(forWritingTo: outputURL),
                  let errors = try? FileHandle(forWritingTo: errorURL) else {
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: errorURL)
                continue
            }
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = output
            process.standardError = errors

            do {
                try process.run()
            } catch {
                try? output.close()
                try? errors.close()
                try? FileManager.default.removeItem(at: outputURL)
                try? FileManager.default.removeItem(at: errorURL)
                continue
            }

            process.waitUntilExit()
            try? output.close()
            try? errors.close()
            let stdout = (try? Data(contentsOf: outputURL)) ?? Data()
            let stderr = (try? Data(contentsOf: errorURL)) ?? Data()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
            guard process.terminationStatus == 0 else {
                let message = String(data: stderr, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw ZLibraryError.commandFailed(
                    message?.isEmpty == false
                        ? message!
                        : "zlib exited with status \(process.terminationStatus). Check your login with `zlib login`."
                )
            }
            return String(data: stdout, encoding: .utf8) ?? ""
        }
        throw ZLibraryError.cliMissing
    }
}

actor ZLibraryPersistence {
    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("z-library.json")
    }

    func load() -> ZLibrarySavedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(ZLibrarySavedState.self, from: data) else {
            return ZLibrarySavedState()
        }
        return state
    }

    func save(_ state: ZLibrarySavedState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
