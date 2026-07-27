import Darwin
import Foundation
import VehlaStoreSDK

private struct ExtensionManifest: Decodable {
    struct Command: Decodable {
        let id: String
        let title: String
        let workspaceID: String?
    }

    struct Workspace: Decodable {
        let id: String
        let title: String
    }

    struct DockWidget: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let systemImage: String
        let preferredPopupWidth: Double
        let preferredPopupHeight: Double
        let supportedSurfaces: [String]

        private enum CodingKeys: String, CodingKey {
            case id, title, subtitle, systemImage
            case preferredPopupWidth, preferredPopupHeight
            case supportedSurfaces
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            subtitle = try container.decodeIfPresent(
                String.self,
                forKey: .subtitle
            )
            systemImage = try container.decodeIfPresent(
                String.self,
                forKey: .systemImage
            ) ?? "shippingbox"
            preferredPopupWidth = try container.decodeIfPresent(
                Double.self,
                forKey: .preferredPopupWidth
            ) ?? 420
            preferredPopupHeight = try container.decodeIfPresent(
                Double.self,
                forKey: .preferredPopupHeight
            ) ?? 520
            supportedSurfaces = try container.decodeIfPresent(
                [String].self,
                forKey: .supportedSurfaces
            ) ?? ["compact"]
        }
    }

    let apiVersion: Int
    let id: String
    let name: String
    let version: String
    let runtime: String?
    let entrypoint: String
    let commands: [Command]
    let capabilities: [StoreCapability]?
    let workspaces: [Workspace]?
    let dockWidgets: [DockWidget]?

    private enum CodingKeys: String, CodingKey {
        case apiVersion, id, name, version, runtime, entrypoint
        case commands, capabilities, workspaces, dockWidgets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try container.decode(Int.self, forKey: .apiVersion)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        entrypoint = try container.decode(String.self, forKey: .entrypoint)
        commands = try container.decodeIfPresent(
            [Command].self,
            forKey: .commands
        ) ?? []
        capabilities = try container.decodeIfPresent(
            [StoreCapability].self,
            forKey: .capabilities
        )
        workspaces = try container.decodeIfPresent(
            [Workspace].self,
            forKey: .workspaces
        )
        dockWidgets = try container.decodeIfPresent(
            [DockWidget].self,
            forKey: .dockWidgets
        )
    }
}

private struct InvocationRequest: Encodable {
    let jsonrpc = "2.0"
    let id: String
    let method = "store.invoke"
    let params: StoreInvocation
}

private enum CLIError: LocalizedError {
    case usage(String)
    case invalidPackage(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let detail),
             .invalidPackage(let detail),
             .commandFailed(let detail):
            return detail
        }
    }
}

private final class CLIOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var storage = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit + 1 - storage.count)
        if remaining > 0 {
            storage.append(data.prefix(remaining))
        }
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@main
private struct VehlaSwiftCLI {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(
                Data("error: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            printHelp()
            return
        }
        switch command {
        case "validate":
            guard arguments.count == 2 else {
                throw CLIError.usage(
                    "Usage: vehla-swift validate <extension-directory>"
                )
            }
            let package = try validatePackage(at: arguments[1])
            printValidation(package)
        case "build":
            guard arguments.count == 2 else {
                throw CLIError.usage(
                    "Usage: vehla-swift build <extension-directory>"
                )
            }
            let root = packageRoot(arguments[1])
            let buildScript = root.appendingPathComponent("build.sh")
            guard FileManager.default.fileExists(atPath: buildScript.path) else {
                throw CLIError.invalidPackage(
                    "The extension does not contain build.sh."
                )
            }
            try runProcess(
                executable: URL(fileURLWithPath: "/bin/zsh"),
                arguments: [buildScript.path],
                currentDirectory: root
            )
            let package = try validatePackage(at: root.path)
            printValidation(package)
        case "test":
            guard (3...4).contains(arguments.count) else {
                throw CLIError.usage(
                    "Usage: vehla-swift test <extension-directory> <command-id> [query]"
                )
            }
            let package = try validatePackage(at: arguments[1])
            guard package.manifest.runtime == "executable" else {
                throw CLIError.commandFailed(
                    "Hosted native UI and dock widget bundles cannot be invoked with vehla-swift test."
                )
            }
            let commandID = arguments[2]
            guard package.manifest.commands.contains(where: {
                $0.id == commandID
            }) else {
                throw CLIError.invalidPackage(
                    "Command \(commandID) is not declared in extension.json."
                )
            }
            try test(
                package: package,
                commandID: commandID,
                query: arguments.count == 4 ? arguments[3] : ""
            )
        case "package":
            guard (2...3).contains(arguments.count) else {
                throw CLIError.usage(
                    "Usage: vehla-swift package <extension-directory> [output.zip]"
                )
            }
            let package = try validatePackage(at: arguments[1])
            let output = arguments.count == 3
                ? URL(fileURLWithPath: arguments[2]).standardizedFileURL
                : package.root.deletingLastPathComponent().appendingPathComponent(
                    "\(package.root.lastPathComponent)-\(package.manifest.version).zip"
                )
            guard !FileManager.default.fileExists(atPath: output.path) else {
                throw CLIError.commandFailed(
                    "Output already exists: \(output.path)"
                )
            }
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: [
                    "-c",
                    "-k",
                    "--sequesterRsrc",
                    "--keepParent",
                    package.root.path,
                    output.path,
                ],
                currentDirectory: package.root.deletingLastPathComponent()
            )
            print("Created \(output.path)")
        case "sign":
            guard (2...3).contains(arguments.count) else {
                throw CLIError.usage(
                    "Usage: vehla-swift sign <extension-directory> [identity]"
                )
            }
            let package = try loadPackage(at: arguments[1])
            let identity = arguments.count == 3 ? arguments[2] : "-"
            try runProcess(
                executable: URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: [
                    "--force",
                    "--sign",
                    identity,
                    "--timestamp=none",
                    "--identifier",
                    package.manifest.id,
                    package.entrypoint.path,
                ],
                currentDirectory: package.root
            )
            let validated = try validatePackage(at: arguments[1])
            printValidation(validated)
        case "help", "--help", "-h":
            printHelp()
        default:
            throw CLIError.usage(
                "Unknown command \(command). Run vehla-swift help."
            )
        }
    }

    private struct Package {
        let root: URL
        let manifest: ExtensionManifest
        let entrypoint: URL
        let architectures: [String]
    }

    private static func packageRoot(_ path: String) -> URL {
        let selected = URL(fileURLWithPath: path).standardizedFileURL
        return selected.lastPathComponent == "extension.json"
            ? selected.deletingLastPathComponent()
            : selected
    }

    private static func loadPackage(at path: String) throws -> Package {
        let root = packageRoot(path)
        let manifestURL = root.appendingPathComponent("extension.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            throw CLIError.invalidPackage(
                "extension.json was not found at \(root.path)."
            )
        }
        let manifest: ExtensionManifest
        do {
            manifest = try JSONDecoder().decode(
                ExtensionManifest.self,
                from: data
            )
        } catch {
            throw CLIError.invalidPackage(
                "extension.json is invalid: \(error.localizedDescription)"
            )
        }
        let entrypoint = root.appendingPathComponent(
            manifest.entrypoint
        ).standardizedFileURL
        return Package(
            root: root,
            manifest: manifest,
            entrypoint: entrypoint,
            architectures: []
        )
    }

    private static func validatePackage(at path: String) throws -> Package {
        let package = try loadPackage(at: path)
        let manifest = package.manifest
        guard (1...3).contains(manifest.apiVersion) else {
            throw CLIError.invalidPackage(
                "Unsupported Store API version \(manifest.apiVersion)."
            )
        }
        let runtime = manifest.runtime ?? "node"
        guard runtime == "executable"
                || runtime == "nativeUI"
                || runtime == "dockWidget" else {
            throw CLIError.invalidPackage(
                "Swift extensions require runtime executable, nativeUI, or dockWidget."
            )
        }
        if runtime == "nativeUI" {
            guard manifest.apiVersion == 2,
                  let workspaces = manifest.workspaces,
                  !workspaces.isEmpty,
                  (manifest.capabilities ?? []).contains(.persistentStorage),
                  Set(workspaces.map(\.id)).count == workspaces.count,
                  workspaces.allSatisfy({
                      validIdentifier($0.id) && !$0.title.isEmpty
                  }),
                  manifest.commands.allSatisfy({
                      guard let workspaceID = $0.workspaceID else {
                          return false
                      }
                      return workspaces.contains { $0.id == workspaceID }
                  }) else {
                throw CLIError.invalidPackage(
                    "Native UI packages require API 2, persistentStorage, valid workspaces, and workspace commands."
                )
            }
        } else if runtime == "dockWidget" {
            let widgets = manifest.dockWidgets ?? []
            guard manifest.apiVersion == 3,
                  manifest.workspaces?.isEmpty != false,
                  !widgets.isEmpty,
                  (manifest.capabilities ?? []).contains(.persistentStorage),
                  Set(widgets.map(\.id)).count == widgets.count,
                  widgets.allSatisfy({
                      let surfaces = $0.supportedSurfaces
                      let validSurfaces = Set(["compact", "inline", "popup"])
                      return validIdentifier($0.id)
                          && !$0.title.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                          && !$0.systemImage.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                          && Set(surfaces).count == surfaces.count
                          && Set(surfaces).isSubset(of: validSurfaces)
                          && surfaces.contains("compact")
                          && (280.0...1_200.0).contains($0.preferredPopupWidth)
                          && (220.0...900.0).contains($0.preferredPopupHeight)
                  }) else {
                throw CLIError.invalidPackage(
                    "Dock widget packages require API 3, persistentStorage, valid unique widgets with compact surfaces, popup dimensions in range, and no workspaces."
                )
            }
        } else if manifest.dockWidgets?.isEmpty == false {
            throw CLIError.invalidPackage(
                "Only dockWidget packages may declare dockWidgets."
            )
        }
        guard validIdentifier(manifest.id),
              !manifest.name.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty,
              !manifest.version.isEmpty else {
            throw CLIError.invalidPackage(
                "Package identity or version is invalid."
            )
        }
        guard runtime == "dockWidget" || !manifest.commands.isEmpty,
              Set(manifest.commands.map(\.id)).count
                == manifest.commands.count,
              manifest.commands.allSatisfy({
                  validIdentifier($0.id) && !$0.title.isEmpty
              }) else {
            throw CLIError.invalidPackage(
                "Commands require unique valid IDs and titles."
            )
        }
        guard relativePathIsSafe(manifest.entrypoint),
              package.entrypoint.path.hasPrefix(
                package.root.path.hasSuffix("/")
                    ? package.root.path
                    : package.root.path + "/"
              ) else {
            throw CLIError.invalidPackage(
                "Entrypoint must remain inside the extension directory."
            )
        }
        let nativeExecutable: URL
        if runtime == "nativeUI" || runtime == "dockWidget" {
            guard package.entrypoint.pathExtension == "bundle",
                  let bundle = Bundle(url: package.entrypoint),
                  let executableURL = bundle.executableURL else {
                throw CLIError.invalidPackage(
                    "Hosted native entrypoint must be a bundle with an executable."
                )
            }
            nativeExecutable = executableURL
            try verifyCodeSignature(of: package.entrypoint, deep: true)
        } else {
            guard FileManager.default.isExecutableFile(
                atPath: package.entrypoint.path
            ) else {
                throw CLIError.invalidPackage(
                    "Entrypoint is missing or is not executable: \(manifest.entrypoint)"
                )
            }
            nativeExecutable = package.entrypoint
            try verifyCodeSignature(of: package.entrypoint)
        }
        let architectures = try machOArchitectures(at: nativeExecutable)
        return Package(
            root: package.root,
            manifest: manifest,
            entrypoint: package.entrypoint,
            architectures: architectures
        )
    }

    private static func validIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]{1,127}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func relativePathIsSafe(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains { $0 == "." || $0 == ".." || $0.isEmpty }
    }

    private static func machOArchitectures(
        at executable: URL
    ) throws -> [String] {
        let output = try capturedProcess(
            executable: URL(fileURLWithPath: "/usr/bin/lipo"),
            arguments: ["-archs", executable.path],
            currentDirectory: executable.deletingLastPathComponent()
        )
        let architectures = output.split(whereSeparator: \.isWhitespace)
            .map(String.init)
        guard Set(architectures) == Set(["arm64"]) else {
            throw CLIError.invalidPackage(
                "Entrypoint must be an arm64-only Mach-O executable."
            )
        }
        return architectures
    }

    private static func verifyCodeSignature(
        of executable: URL,
        deep: Bool = false
    ) throws {
        var arguments = [
            "--verify",
            "--strict",
            "--verbose=1",
        ]
        if deep {
            arguments.append("--deep")
        }
        arguments.append(executable.path)
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: arguments,
            currentDirectory: executable.deletingLastPathComponent()
        )
    }

    private static func test(
        package: Package,
        commandID: String,
        query: String
    ) throws {
        guard package.manifest.runtime == "executable" else {
            throw CLIError.commandFailed(
                "Native UI workspaces are opened by Vehla and cannot be invoked with vehla-swift test."
            )
        }
        let capabilities = package.manifest.capabilities ?? []
        var temporaryDataDirectory: URL?
        if capabilities.contains(.persistentStorage) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "vehla-swift-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            temporaryDataDirectory = directory
        }
        defer {
            if let temporaryDataDirectory {
                try? FileManager.default.removeItem(
                    at: temporaryDataDirectory
                )
            }
        }
        let request = InvocationRequest(
            id: "vehla-swift-\(UUID().uuidString)",
            params: StoreInvocation(
                packageID: package.manifest.id,
                commandID: commandID,
                query: query,
                context: StoreInvocationContext(
                    dataDirectory: temporaryDataDirectory?.path,
                    grantedCapabilities: capabilities
                )
            )
        )
        var payload = try JSONEncoder().encode(request)
        payload.append(0x0A)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = package.entrypoint
        process.currentDirectoryURL = package.root
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VEHLA_EXTENSION_BACKGROUND": "1",
            "VEHLA_STORE_API_VERSION": "1",
        ]) { current, _ in current }
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let completed = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in completed.signal() }
        try process.run()
        let outputBuffer = CLIOutputBuffer(limit: 1_048_576)
        let errorBuffer = CLIOutputBuffer(limit: 1_048_576)
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { readers.leave() }
            let handle = output.fileHandleForReading
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                outputBuffer.append(data)
            }
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { readers.leave() }
            let handle = errors.fileHandleForReading
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                errorBuffer.append(data)
            }
        }
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
        if completed.wait(timeout: .now() + 15) == .timedOut {
            process.terminate()
            if completed.wait(timeout: .now() + 2) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = completed.wait(timeout: .now() + 2)
            }
            readers.wait()
            throw CLIError.commandFailed(
                "Extension timed out after 15 seconds."
            )
        }
        readers.wait()
        let response = outputBuffer.data
        let diagnostic = errorBuffer.data
        guard process.terminationStatus == 0 else {
            throw CLIError.commandFailed(
                String(decoding: diagnostic, as: UTF8.self)
            )
        }
        guard response.count <= 1_048_576,
              let object = try? JSONSerialization.jsonObject(with: response),
              let dictionary = object as? [String: Any],
              dictionary["jsonrpc"] as? String == "2.0",
              dictionary["id"] as? String == request.id else {
            throw CLIError.commandFailed(
                "Extension returned an invalid protocol response."
            )
        }
        print(String(decoding: response, as: UTF8.self), terminator: "")
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.commandFailed(
                "\(executable.lastPathComponent) exited with status "
                    + "\(process.terminationStatus)."
            )
        }
    }

    private static func capturedProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw CLIError.commandFailed(
                String(decoding: diagnostic, as: UTF8.self)
            )
        }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func printValidation(_ package: Package) {
        print("Valid Swift extension: \(package.manifest.name)")
        print("Package ID: \(package.manifest.id)")
        print("Version: \(package.manifest.version)")
        print("Entrypoint: \(package.manifest.entrypoint)")
        print("Architectures: \(package.architectures.joined(separator: ", "))")
        print("Code signature: valid")
        switch package.manifest.runtime {
        case "nativeUI":
            print("Execution: in-process native workspace with full app access")
        case "dockWidget":
            print(
                "Execution: in-process dock widgets with full app access "
                    + "(\(package.manifest.dockWidgets?.count ?? 0))"
            )
        default:
            print("Execution: background-only")
        }
    }

    private static func printHelp() {
        print(
            """
            Vehla Swift extension developer tools

            Usage:
              vehla-swift validate <extension-directory>
              vehla-swift build <extension-directory>
              vehla-swift test <extension-directory> <command-id> [query]
              vehla-swift package <extension-directory> [output.zip]
              vehla-swift sign <extension-directory> [identity]
              vehla-swift help

            Commands:
              validate  Validate manifest, Mach-O architectures, and signature.
              build     Run build.sh and validate the resulting package.
              test      Invoke one command with Vehla's runtime limits.
              package   Create a versioned ZIP after validation.
              sign      Code-sign the native entrypoint; defaults to ad hoc.
            """
        )
    }
}
