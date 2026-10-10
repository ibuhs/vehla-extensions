import AppKit
import Foundation
import VehlaNativeUISDK

@main
@MainActor
enum WorkspaceLoading {
    static func main() throws {
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? NSObject.Type,
              let plugin = type.init() as? any VehlaNativeWorkspacePlugin,
              plugin.apiVersion == VehlaNativeUIAPIVersion,
              plugin.workspaces.first?.id == "puresnitch" else {
            throw NSError(domain: "PureSnitchLoading", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The signed bundle does not load through Vehla's native workspace contract."])
        }
        print("Loaded PureSnitch bundle and native workspace contract.")
        if CommandLine.arguments.count > 2 {
            // Optional offscreen visual QA. No helper registration or enforcement.
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let output = URL(fileURLWithPath: CommandLine.arguments[2])
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for command in ["open", "rules", "settings"] {
                let context = VehlaWorkspaceContext(
                    packageID: "com.kailalabs.vehla.puresnitch", workspaceID: "puresnitch", dataDirectory: output,
                    launchRequest: VehlaWorkspaceLaunchRequest(commandID: command),
                    theme: VehlaWorkspaceTheme(isDark: true, accentColor: .controlAccentColor,
                        primaryTextColor: .labelColor, secondaryTextColor: .secondaryLabelColor, surfaceColor: .windowBackgroundColor),
                    secretLookup: { _ in nil }, actionHandler: { _ in }
                )
                let controller = try plugin.makeViewController(workspaceID: "puresnitch", context: context)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentViewController = controller
                window.setContentSize(NSSize(width: 1180, height: 760))
                controller.view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
                    throw NSError(domain: "PureSnitchLoading", code: 2)
                }
                controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(command + ".png"))
                plugin.workspaceWillClose?("puresnitch")
                window.close()
            }
            print("Rendered Monitor, Rules, and Settings to \(output.path).")
        }
    }
}
