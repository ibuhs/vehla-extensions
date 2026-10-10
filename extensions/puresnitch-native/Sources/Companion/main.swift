import Foundation
import ServiceManagement
import Darwin

// This executable runs from its own .app bundle. SMAppService must belong to
// that bundle, never Bundle.main of the in-process Vehla workspace.
let arguments = Array(CommandLine.arguments.dropFirst())
var response: [String: Any] = [:]
do {
    guard arguments.count == 1, ["--status", "--register", "--unregister"].contains(arguments[0]) else {
        throw NSError(domain: CompanionPolicy.bundleID, code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Expected --status, --register, or --unregister."])
    }
    // Even SMAppService.status updates Background Task Management's bundle URL.
    // Querying a packaged/test copy with the same ID can redirect the registered
    // daemon to that copy. Validate the location before constructing the service
    // for every operation, including status.
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    let app = CompanionPolicy.applicationURL(home: home)
    try CompanionPolicy.validateInstallationDirectory(home: home, applications: app.deletingLastPathComponent())
    guard Bundle.main.bundleIdentifier == CompanionPolicy.bundleID,
          Bundle.main.bundleURL.resolvingSymlinksInPath() == app.resolvingSymlinksInPath() else {
        throw NSError(domain: CompanionPolicy.bundleID, code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "Install the service in your Applications folder first."])
    }
    let service = SMAppService.daemon(plistName: "com.kailalabs.vehla.puresnitch.helper.plist")
    switch arguments[0] {
    case "--register":
        if service.status != .enabled && service.status != .requiresApproval { try service.register() }
    case "--unregister":
        // The workspace verifies root-owned cleanup through XPC before this.
        // The synchronous overload returns before the job has terminated.
        // Apple's completion overload confirms it is safe to re-register.
        let finished = DispatchSemaphore(value: 0)
        var removalError: Error?
        service.unregister { error in
            removalError = error
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 15) == .success else {
            throw NSError(domain: CompanionPolicy.bundleID, code: 5,
                          userInfo: [NSLocalizedDescriptionKey: "macOS has not finished removing the helper. Try Repair Helper again."])
        }
        if let removalError { throw removalError }
    default: break
    }
    response = ["status": service.status.rawValue]
} catch {
    response = ["error": String(error.localizedDescription.prefix(1024))]
}
let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([10]))
exit(response["error"] == nil ? 0 : 1)
