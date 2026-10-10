import Foundation
import CoreServices
import ServiceManagement
import Security
import Darwin

@MainActor
final class CompanionService {
    static let shared = CompanionService()
    private(set) var status: SMAppService.Status = .notRegistered
    private let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    var installedApp: URL { CompanionPolicy.applicationURL(home: home) }
    private var bundledApp: URL {
        Bundle(for: PureSnitchWorkspacePlugin.self).bundleURL
            .appendingPathComponent("Contents/Resources/" + CompanionPolicy.appName, isDirectory: true)
    }

    func refresh() async throws {
        guard FileManager.default.fileExists(atPath: installedApp.path) else {
            status = .notRegistered
            return
        }
        status = try await CompanionWorker.run(app: installedApp, argument: "--status", reference: bundledApp)
    }

    func register() async throws {
        try await CompanionWorker.install(source: bundledApp, destination: installedApp, home: home)
        status = try await CompanionWorker.run(app: installedApp, argument: "--register", reference: bundledApp)
    }

    func unregister(completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                status = try await CompanionWorker.run(app: installedApp, argument: "--unregister", reference: bundledApp)
                completionHandler(nil)
            } catch { completionHandler(error) }
        }
    }
}

enum CompanionWorker {
    /// Neither subprocess waits nor code-signature verification run on the UI actor.
    @concurrent
    static func run(app: URL, argument: String, reference: URL) async throws -> SMAppService.Status {
        try Task.checkCancellation()
        _ = try isReleaseSigned(reference)
        try validate(app, signed: isReleaseSigned(app))
        let result = try execute(app: app, argument: argument)
        try Task.checkCancellation()
        return result
    }

    // Keep blocking Foundation process work in a synchronous worker function.
    private static func execute(app: URL, argument: String) throws -> SMAppService.Status {
        let process = Process()
        process.executableURL = app.appendingPathComponent("Contents/MacOS/VehlaPureSnitchService")
        process.arguments = [argument]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + 20) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            throw failure("The service installer timed out. Check Login Items and try again.")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard data.count < 8192,
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw failure("The service installer returned an unreadable response.")
        }
        if let message = payload["error"] as? String { throw failure(message) }
        guard process.terminationStatus == 0,
              let raw = payload["status"] as? Int,
              let status = SMAppService.Status(rawValue: raw) else {
            throw failure("The service installer did not return a valid registration status.")
        }
        return status
    }

    @concurrent
    static func install(source: URL, destination: URL, home: URL,
                        registerApplication: @Sendable (URL) throws -> Void = { try refreshApplicationRegistration($0) }) async throws {
        try Task.checkCancellation()
        let files = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try CompanionPolicy.validateInstallationDirectory(home: home, applications: parent)
        let signed = try isReleaseSigned(source)
        try validate(source, signed: signed)
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let exists = files.fileExists(atPath: destination.path)
        if exists {
            let metadata = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard metadata.isSymbolicLink != true else { throw failure("The installed service cannot be a symbolic link.") }
            // A local development installation can be upgraded to a release
            // build. Validate the old copy by its own accepted signing mode;
            // the replacement always uses the new bundle's signature policy.
            try validate(destination, signed: isReleaseSigned(destination))
            // Compare signed executable content, rather than just a version string.
            let relative = "Contents/MacOS/VehlaPureSnitchService"
            let helper = "Contents/MacOS/PureSnitchHelper"
            if files.contentsEqual(atPath: source.appendingPathComponent(relative).path, andPath: destination.appendingPathComponent(relative).path),
               files.contentsEqual(atPath: source.appendingPathComponent(helper).path, andPath: destination.appendingPathComponent(helper).path) {
                try registerApplication(destination)
                return
            }
            let status = try await run(app: destination, argument: "--status", reference: source)
            guard status == .notRegistered || status == .notFound else {
                throw failure("Use Repair Helper to update the installed service after verified firewall cleanup.")
            }
        }
        let staged = parent.appendingPathComponent(".vehla-puresnitch-install-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".vehla-puresnitch-backup-\(UUID().uuidString).app")
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: source, to: staged)
        try validate(staged, signed: signed)
        try Task.checkCancellation()
        if exists { try files.moveItem(at: destination, to: backup) }
        var replacementInstalled = false
        do {
            try files.moveItem(at: staged, to: destination)
            replacementInstalled = true
            // SMAppService resolves the installed app through Launch Services.
            // An atomic bundle replacement can leave its cached URL/signature
            // pointing at the old inode, even though the path is unchanged.
            try registerApplication(destination)
        }
        catch {
            do {
                if replacementInstalled { try files.removeItem(at: destination) }
                if exists {
                    try files.moveItem(at: backup, to: destination)
                    try? registerApplication(destination)
                }
            } catch {
                throw failure("The service update could not be rolled back. The previous service is saved at \(backup.path).")
            }
            throw error
        }
        if exists { try? files.removeItem(at: backup) }
    }

    private static func refreshApplicationRegistration(_ app: URL) throws {
        let result = LSRegisterURL(app as CFURL, true)
        guard result == noErr else {
            throw failure("macOS could not refresh the installed service registration (\(result)).")
        }
    }

    private static func isReleaseSigned(_ app: URL) throws -> Bool {
        let code = try staticCode(app)
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { throw failure("Cannot read the bundled service signature.") }
        if let team = values[kSecCodeInfoTeamIdentifier as String] as? String {
            guard team == CompanionPolicy.teamID else { throw failure("The service was signed by an unexpected developer.") }
            return true
        }
        // CS_ADHOC (Security/CSCommon.h). The SDK does not expose the C spelling
        // as a Swift global; inspect its documented signature flag value.
        guard ((values[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0) & 0x0002 != 0 else {
            throw failure("The service has no valid developer or local development signature.")
        }
        return false
    }

    private static func validate(_ app: URL, signed: Bool) throws {
        var requirement: SecRequirement?
        let text = CompanionPolicy.codeRequirement(identifier: CompanionPolicy.bundleID, signed: signed)
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(try staticCode(app), SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate), requirement) == errSecSuccess else {
            throw failure("The PureSnitch service signature is invalid or belongs to another application.")
        }
    }

    private static func staticCode(_ url: URL) throws -> SecStaticCode {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw failure("The PureSnitch service is missing from this package.")
        }
        return code
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: CompanionPolicy.bundleID, code: 4, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
