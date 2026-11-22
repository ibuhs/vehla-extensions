import Foundation

/// Reads and changes real system state through command-line tools.
public struct SystemControls: Sendable {
    public init() {}

    public func isOn(_ toggle: ToggleID) async -> Bool {
        switch toggle {
        case .darkMode:
            return Parsers.isDarkMode(await Shell.run("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]))
        case .mute:
            let r = await Shell.run("/usr/bin/osascript", ["-e", "output muted of (get volume settings)"])
            return r.ok && Parsers.isTrue(r.output)
        case .desktopIcons:
            return Parsers.desktopIconsShown(await Shell.run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"]))
        case .keepAwake:
            return false // owned by the extension: it holds the caffeinate process
        }
    }

    public func set(_ toggle: ToggleID, on: Bool) async throws {
        switch toggle {
        case .darkMode:
            try check(await Shell.run("/usr/bin/osascript", ["-e",
                "tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)"]), "Dark Mode")
        case .mute:
            try check(await Shell.run("/usr/bin/osascript", ["-e", "set volume output muted \(on)"]), "Mute")
        case .desktopIcons:
            try check(await Shell.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", on ? "true" : "false"]), "Desktop Icons")
            await Shell.run("/usr/bin/killall", ["Finder"])
        case .keepAwake:
            break
        }
    }

    public func listShortcuts() async -> [String] {
        let r = await Shell.run("/usr/bin/shortcuts", ["list"])
        return r.ok ? Parsers.shortcuts(r.output) : []
    }

    public func runShortcut(_ name: String) async throws {
        try check(await Shell.run("/usr/bin/shortcuts", ["run", name], timeout: 120), "Shortcut \(name)")
    }

    public func open(app name: String) async throws {
        guard !name.isEmpty, !name.hasPrefix("-") else { throw ShellError.failed("Open \(name) (not an app name)", 22) }
        try check(await Shell.run("/usr/bin/open", ["-a", name]), "Open \(name)")
    }

    public func open(url: String) async throws {
        // A scheme is required, which also keeps a value like "-a Something" from being read as an option.
        guard let parsed = URL(string: url), let scheme = parsed.scheme, !scheme.isEmpty, !url.hasPrefix("-") else {
            throw ShellError.failed("Open \(url) (not a valid URL)", 22)
        }
        try check(await Shell.run("/usr/bin/open", [parsed.absoluteString]), "Open \(url)")
    }

    private func check(_ result: ShellResult, _ what: String) throws {
        if !result.ok { throw ShellError.failed(what, result.status) }
    }
}
