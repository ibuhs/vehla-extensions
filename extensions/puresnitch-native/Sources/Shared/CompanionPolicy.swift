import Foundation

/// Shared installation constraints, also compiled into the companion process.
enum CompanionPolicy {
    static let appName = "Vehla PureSnitch Service.app"
    static let bundleID = "com.kailalabs.vehla.puresnitch.service"
    static let helperID = "com.kailalabs.vehla.puresnitch.helper"
    static let hostID = "com.kc.ibuhs.Vehla"
    static let teamID = "2ZFXP6CM2U"

    static func applicationURL(home: URL) -> URL {
        home.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    static func validateInstallationDirectory(home: URL, applications: URL) throws {
        let resolvedHome = home.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedApplications = applications.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedApplications == resolvedHome + "/Applications" else {
            throw NSError(domain: bundleID, code: 1, userInfo: [NSLocalizedDescriptionKey:
                "The service must be installed in your own Applications folder. A symlink to another folder is not supported."])
        }
    }

    static func codeRequirement(identifier: String, signed: Bool) -> String {
        let identity = "identifier \"\(identifier)\""
        if !signed { return identity }
        return "anchor apple generic and \(identity) and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}
