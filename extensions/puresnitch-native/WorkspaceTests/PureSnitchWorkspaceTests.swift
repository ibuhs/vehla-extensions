import XCTest
import AppKit
import SwiftUI
import ServiceManagement
import VehlaNativeUISDK
@testable import PureSnitchWorkspace

final class PureSnitchWorkspaceTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }

    func testInstallationRejectsApplicationsSymlinkOutsideHome() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home")
        let outside = temp.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let apps = home.appendingPathComponent("Applications")
        try CompanionPolicy.validateInstallationDirectory(home: home, applications: apps)
        try FileManager.default.createSymbolicLink(at: apps, withDestinationURL: outside)
        XCTAssertThrowsError(try CompanionPolicy.validateInstallationDirectory(home: home, applications: apps))
    }

    func testHelperAndCompanionHaveDistinctIdentities() throws {
        XCTAssertEqual(AppConstants.bundleIdGUI, "com.kc.ibuhs.Vehla")
        XCTAssertEqual(AppConstants.xpcMachServiceName, CompanionPolicy.helperID)
        XCTAssertNotEqual(CompanionPolicy.helperID, "io.moamenbasel.puresnitch.helper")
        XCTAssertEqual(AppConstants.sharedDataDir.path, "/Library/Application Support/Vehla PureSnitch")
        XCTAssertEqual(AppConstants.version, "1.0.0")
        let release = CompanionPolicy.codeRequirement(identifier: CompanionPolicy.hostID, signed: true)
        XCTAssertTrue(release.contains("anchor apple generic"))
        XCTAssertTrue(release.contains(CompanionPolicy.teamID))
        XCTAssertEqual(CompanionPolicy.codeRequirement(identifier: CompanionPolicy.hostID, signed: false),
                       "identifier \"com.kc.ibuhs.Vehla\"")
    }

    func testStoredConfigurationRoundTrip() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let store = try RuleStore(path: temp.appendingPathComponent("policy.sqlite").path)
        XCTAssertEqual(store.allBlocklists().count, 8)
        XCTAssertEqual(store.allProfiles().count, 4)
        try store.setSetting("doh_url", "https://dns.quad9.net/dns-query")
        let configuration = HelperConfiguration(blocklists: store.allBlocklists(), profiles: store.allProfiles(),
                                                dohUpstream: try XCTUnwrap(store.getSetting("doh_url")))
        let restored = try JSONDecoder().decode(HelperConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(restored.dohUpstream, "https://dns.quad9.net/dns-query")
        XCTAssertEqual(restored.blocklists.map(\.id), configuration.blocklists.map(\.id))
        XCTAssertEqual(restored.profiles.map(\.name), configuration.profiles.map(\.name))
        let helper = try String(contentsOf: root.appendingPathComponent("Sources/Helper/HelperService.swift"))
        let configurationMethod = try XCTUnwrap(helper.components(separatedBy: "func getConfiguration").last)
            .components(separatedBy: "func setMode").first ?? ""
        XCTAssertTrue(configurationMethod.contains("authorizeCurrentXPCRequest"))
        XCTAssertTrue(helper.contains("if let upstream = store.getSetting(\"doh_url\") { dns.dohURL = upstream }"))
    }

    func testCompanionInstallationCopiesVerifiedProductsIdempotently() async throws {
        let app = root.appendingPathComponent("bin/PureSnitchWorkspace.bundle/Contents/Resources/" + CompanionPolicy.appName)
        guard FileManager.default.fileExists(atPath: app.path) else { throw XCTSkip("Run build.sh first.") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("puresnitch-install-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let destination = CompanionPolicy.applicationURL(home: home)
        let registered = expectation(description: "Explicit installation refreshes only the installed app")
        registered.expectedFulfillmentCount = 2
        let registerApplication: @Sendable (URL) throws -> Void = { url in
            XCTAssertEqual(url, destination)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/PureSnitchHelper").path))
            registered.fulfill()
        }
        // Never register test copies in the real Launch Services database.
        try await CompanionWorker.install(source: app, destination: destination, home: home,
                                          registerApplication: registerApplication)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/MacOS/PureSnitchHelper").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Contents/Resources/LICENSE").path))
        try await CompanionWorker.install(source: app, destination: destination, home: home,
                                          registerApplication: registerApplication)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Applications").path),
                       [CompanionPolicy.appName])
        await fulfillment(of: [registered], timeout: 1)
    }

    @MainActor
    func testWorkspaceContractAndCloseLifecycle() throws {
        let plugin = PureSnitchWorkspacePlugin()
        XCTAssertEqual(plugin.apiVersion, VehlaNativeUIAPIVersion)
        XCTAssertEqual(plugin.workspaces.count, 1)
        XCTAssertEqual(plugin.workspaces[0].id, "puresnitch")
        XCTAssertEqual(plugin.workspaces[0].dismissBehavior, .persistent)
        let state = AppState()
        XCTAssertFalse(state.enforcementEnabled)
        XCTAssertFalse(state.helperConnected)
        state.helper.disconnect()
        XCTAssertTrue(state.pendingAlerts.isEmpty)
        XCTAssertFalse(state.helperConnected)
        (plugin as any VehlaNativeWorkspacePlugin).workspaceWillClose?("puresnitch")
    }

    func testFailedApplicationRegistrationRollsBackNewInstallation() async throws {
        let app = root.appendingPathComponent("bin/PureSnitchWorkspace.bundle/Contents/Resources/" + CompanionPolicy.appName)
        guard FileManager.default.fileExists(atPath: app.path) else { throw XCTSkip("Run build.sh first.") }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("puresnitch-rollback-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let destination = CompanionPolicy.applicationURL(home: home)
        do {
            try await CompanionWorker.install(source: app, destination: destination, home: home,
                                              registerApplication: { _ in
                throw NSError(domain: "registration-test", code: 1)
            })
            XCTFail("Failed metadata registration left an installed service")
        } catch {
            XCTAssertEqual((error as NSError).domain, "registration-test")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent("Applications").path), [])
    }

    @MainActor
    func testDismantlingPreviousControllerKeepsReplacementSubscriptionActive() async throws {
        _ = NSApplication.shared
        let plugin: any VehlaNativeWorkspacePlugin = PureSnitchWorkspacePlugin()
        let context = VehlaWorkspaceContext(
            packageID: "com.kailalabs.vehla.puresnitch", workspaceID: "puresnitch",
            dataDirectory: FileManager.default.temporaryDirectory,
            launchRequest: VehlaWorkspaceLaunchRequest(commandID: "open"),
            theme: VehlaWorkspaceTheme(isDark: true, accentColor: .controlAccentColor,
                primaryTextColor: .labelColor, secondaryTextColor: .secondaryLabelColor,
                surfaceColor: .windowBackgroundColor),
            secretLookup: { _ in nil }, actionHandler: { _ in }
        )
        var previous: NSViewController? = try plugin.makeViewController(workspaceID: "puresnitch", context: context)
        let previousState = try XCTUnwrap((previous as? NSHostingController<PureSnitchWorkspaceView>)?.rootView.state)
        var replacement: NSViewController? = try plugin.makeViewController(workspaceID: "puresnitch", context: context)
        let replacementState = try XCTUnwrap((replacement as? NSHostingController<PureSnitchWorkspaceView>)?.rootView.state)
        weak var previousController = previous
        weak var replacementController = replacement

        // This is SwiftUI's create-new / dismantle-old ordering. The callback
        // has only the shared workspace ID, so it must not close the new client.
        plugin.workspaceWillClose?("puresnitch")
        XCTAssertTrue(replacementState.helper.workspaceActive)

        // AppKit can retain a hidden controller after its workspace closes.
        // Disappearance must stop that subscription before deallocation.
        (replacement as? PureSnitchWorkspaceController)?.viewWillDisappear()
        XCTAssertFalse(replacementState.helper.workspaceActive)
        (replacement as? PureSnitchWorkspaceController)?.viewWillAppear()
        XCTAssertTrue(replacementState.helper.workspaceActive)
        previous = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(previousController)
        XCTAssertFalse(previousState.helper.workspaceActive)
        XCTAssertTrue(replacementState.helper.workspaceActive)

        replacement = nil
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(replacementController)
        XCTAssertFalse(replacementState.helper.workspaceActive)
        XCTAssertFalse(replacementState.enforcementEnabled)
    }

    func testPassiveOpeningAndFirewallNamespaceGuards() throws {
        let plugin = try String(contentsOf: root.appendingPathComponent("Sources/GUI/App/PureSnitchWorkspacePlugin.swift"))
        XCTAssertFalse(plugin.contains("registerDaemon()"))
        XCTAssertFalse(plugin.contains("NSApp.terminate"))
        XCTAssertTrue(plugin.contains("Task { @MainActor in state.helper.disconnect() }"))
        let client = try String(contentsOf: root.appendingPathComponent("Sources/GUI/App/HelperClient.swift"))
        XCTAssertTrue(client.contains("await self.updateInstallState()"))
        XCTAssertTrue(client.contains("prepareHelperForUnregistration"))
        XCTAssertTrue(client.contains("self.workspaceActive, !self.isRepairing"))
        let installer = try String(contentsOf: root.appendingPathComponent("Sources/GUI/App/CompanionService.swift"))
        XCTAssertTrue(installer.contains("LSRegisterURL(app as CFURL, true)"))
        let passiveStatus = try XCTUnwrap(installer.components(separatedBy: "func refresh() async throws {").last)
            .components(separatedBy: "func register() async throws {").first ?? ""
        XCTAssertFalse(passiveStatus.contains("registerApplication"))
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/GUI/Views/SettingsView.swift"))
        XCTAssertFalse(settings.contains("SMAppService.mainApp"))
        let pf = try String(contentsOf: root.appendingPathComponent("Sources/Helper/PFManager.swift"))
        XCTAssertTrue(pf.contains("com.apple/vehla-puresnitch"))
        XCTAssertFalse(pf.contains("\"com.apple/puresnitch\""))
        XCTAssertFalse(pf.contains("\"/var/run/puresnitch"))
        XCTAssertFalse(pf.contains("\"/etc/pf.anchors/puresnitch\""))
        let main = try String(contentsOf: root.appendingPathComponent("Sources/Helper/main.swift"))
        XCTAssertTrue(main.contains("\nRunLoop.main.run()"))
        XCTAssertFalse(main.contains("\ndispatchMain()"))
        let helper = try String(contentsOf: root.appendingPathComponent("Sources/Helper/HelperService.swift"))
        let startup = try XCTUnwrap(helper.components(separatedBy: "func start() {").last)
            .components(separatedBy: "func shutdown()").first ?? ""
        XCTAssertFalse(startup.contains("netmon.start()"))
        let daemonData = try Data(contentsOf: root.appendingPathComponent("Sources/Helper/Launchd.plist"))
        let daemon = try XCTUnwrap(PropertyListSerialization.propertyList(from: daemonData, format: nil) as? [String: Any])
        XCTAssertEqual((daemon["KeepAlive"] as? [String: Bool])?["SuccessfulExit"], false)
    }

    func testIdleExitPreservesClientsAndFirewallState() {
        for bits in 0..<32 {
            let inputs = (0..<5).map { bits & (1 << $0) != 0 }
            XCTAssertEqual(HelperLifetime.canExit(hasClients: inputs[0], enforcementDesired: inputs[1],
                migrationPending: inputs[2], pfActive: inputs[3], dnsActive: inputs[4]), bits == 0)
        }
    }

    func testPackagedCompanionPassiveStatusAndForeignIdentityRejection() async throws {
        let app = root.appendingPathComponent("bin/PureSnitchWorkspace.bundle/Contents/Resources/" + CompanionPolicy.appName)
        guard FileManager.default.fileExists(atPath: app.path) else { throw XCTSkip("Run build.sh first for packaging checks.") }
        do {
            _ = try await CompanionWorker.run(app: app, argument: "--status", reference: app)
            XCTFail("An embedded service queried SMAppService and could redirect a live registration")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Applications folder")) }
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Companion/main.swift"))
        let locationCheck = try XCTUnwrap(source.range(of: "guard Bundle.main.bundleIdentifier"))
        let serviceCreation = try XCTUnwrap(source.range(of: "let service = SMAppService.daemon"))
        XCTAssertLessThan(locationCheck.lowerBound, serviceCreation.lowerBound)
        XCTAssertTrue(source.contains("service.unregister { error in"))
        XCTAssertTrue(source.contains("finished.wait(timeout:"))
        do {
            _ = try await CompanionWorker.run(app: URL(fileURLWithPath: "/System/Applications/Calculator.app"),
                                             argument: "--status", reference: app)
            XCTFail("A foreign application passed service validation")
        } catch { XCTAssertTrue(error.localizedDescription.contains("signature")) }
    }
}
