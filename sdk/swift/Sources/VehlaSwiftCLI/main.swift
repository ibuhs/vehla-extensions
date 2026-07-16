import Foundation
import VehlaStoreSDK

private struct ExtensionManifest: Decodable {
    struct Command: Decodable {
        let id: String
        let title: String
    }

    let apiVersion: Int
    let id: String
    let name: String
    let version: String
    let runtime: String?
    let entrypoint: String
    let commands: [Command]
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
        guard manifest.apiVersion == 1 else {
            throw CLIError.invalidPackage(
                "Unsupported Store API version \(manifest.apiVersion)."
            )
        }
        guard manifest.runtime == "executable" else {
            throw CLIError.invalidPackage(
                "Swift extensions require runtime executable."
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
        guard !manifest.commands.isEmpty,
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
        guard FileManager.default.isExecutableFile(
            atPath: package.entrypoint.path
        ) else {
            throw CLIError.invalidPackage(
                "Entrypoint is missing or is not executable: \(manifest.entrypoint)"
            )
        }
        let architectures = try machOArchitectures(
            at: package.entrypoint
        )
        try verifyCodeSignature(of: package.entrypoint)
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

    private static func verifyCodeSignature(of executable: URL) throws {
        try runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: [
                "--verify",
                "--strict",
                "--verbose=1",
                executable.path,
            ],
            currentDirectory: executable.deletingLastPathComponent()
        )
    }

    private static func test(
        package: Package,
        commandID: String,
        query: String
    ) throws {
        let request = InvocationRequest(
            id: "vehla-swift-\(UUID().uuidString)",
            params: StoreInvocation(
                packageID: package.manifest.id,
                commandID: commandID,
                query: query,
                context: StoreInvocationContext()
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
        try input.fileHandleForWriting.write(contentsOf: payload)
        try input.fileHandleForWriting.close()
        if completed.wait(timeout: .now() + 15) == .timedOut {
            process.terminate()
            throw CLIError.commandFailed(
                "Extension timed out after 15 seconds."
            )
        }
        let response = output.fileHandleForReading.readDataToEndOfFile()
        let diagnostic = errors.fileHandleForReading.readDataToEndOfFile()
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
        print("Execution: background-only")
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
