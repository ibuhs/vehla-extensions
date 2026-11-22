import AppKit
import Foundation

/// Vehla's Notch / Island extension SDK (Store API 4, `runtime: "notch"`).
///
/// A Notch extension can do two things:
///
/// - show a **live activity** in the closed Notch (and in the floating Island's title): an icon, a title, a
///   short detail and up to two buttons, described as data and drawn by Vehla;
/// - add a **tab** to the open Notch / Island, drawn by the extension's own view controller.
///
/// This SDK is a static library: it is compiled into your bundle and Vehla embeds no framework for it. The
/// two sides meet only through the Objective-C protocols `VehlaNotchHost` and `VehlaNotchPlugin`, which Vehla
/// declares under the same names, so nothing of yours is loaded, and no memory is used, until the user turns
/// your extension on. A tab's view controller is made when the tab comes on screen and released when it
/// leaves; do not keep it alive yourself.
public let VehlaNotchAPIVersion = 4

// MARK: - Wire contract (declared by Vehla under the same Objective-C names)

/// What Vehla gives an extension. Only Foundation and AppKit types cross this boundary.
@objc(VehlaNotchHost)
public protocol VehlaNotchHost: NSObjectProtocol {
    var packageID: String { get }
    /// A folder that belongs to this extension (`persistentStorage`).
    var dataDirectoryPath: String { get }
    /// Capabilities from the manifest that the user allowed.
    var capabilities: [String] { get }
    /// `isDark` (Bool) and `accent` (NSColor). The Notch itself is always dark.
    func themeInfo() -> [String: Any]
    /// Shows or updates a live activity. Keys: see `VehlaNotchActivity`.
    func showActivity(_ info: [String: Any])
    func endActivity(_ activityID: String)
    /// Opens the Notch on one of this extension's tabs.
    func openTab(_ tabID: String)
    /// `openURL` (`url`), `copyText` (`text`), `log` (`message`). False when refused or unknown.
    func perform(_ action: String, info: [String: Any]) -> Bool
    /// A Keychain value declared under `secrets` in the manifest.
    func secret(named secretID: String) -> String?
}

/// Implemented by the bundle's principal class. Every call arrives on the main thread and must return
/// quickly; start long work in tasks you can cancel.
@objc(VehlaNotchPlugin)
public protocol VehlaNotchPlugin: NSObjectProtocol {
    var apiVersion: Int { get }

    /// The extension is in use: with `"background": true` when the Notch starts, otherwise just before
    /// its first tab is shown. Keep the host for later calls.
    @MainActor func notchDidStart(_ host: any VehlaNotchHost)

    /// The Notch stopped, or the extension was turned off, updated or removed. Stop timers and tasks.
    @MainActor @objc optional func notchWillStop()

    /// A fresh view controller for a tab declared in the manifest. Vehla sizes it and releases it when the
    /// tab leaves the screen.
    @MainActor @objc optional func makeTabViewController(_ tabID: String) -> NSViewController?

    @MainActor @objc optional func tab(_ tabID: String, isVisible: Bool)

    /// A button on a live activity was pressed; an empty `actionID` means the activity itself was clicked.
    @MainActor @objc optional func activity(_ activityID: String, performAction actionID: String)

    @MainActor @objc optional func themeDidChange()
}

// MARK: - Swift conveniences

/// A button on a live activity. With a `systemImage` the button shows the symbol alone and `title` becomes
/// its tooltip.
public struct VehlaNotchActivityButton: Sendable, Equatable {
    public var id: String
    public var title: String
    public var systemImage: String?

    public init(id: String, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// A live activity, described as data. Vehla draws it: the symbol and title left of the camera, the detail
/// and buttons right of it. Text that doesn't fit is cut off, so keep it short.
public struct VehlaNotchActivity: Sendable, Equatable {
    /// One of the `activities` ids in the manifest.
    public var id: String
    public var systemImage: String
    public var title: String
    public var detail: String?
    /// The symbol's colour as "#RRGGBB"; white when nil.
    public var tintHex: String?
    /// 0...1 draws a small ring around the symbol.
    public var progress: Double?
    /// Counts on the right instead of `detail`: down to `timerEnd`, or up from `timerStart`.
    public var timerEnd: Date?
    public var timerStart: Date?
    /// Seconds until Vehla removes it by itself; nil keeps it until `end` (at most eight hours).
    public var duration: TimeInterval?
    /// At most two.
    public var buttons: [VehlaNotchActivityButton]

    public init(id: String, systemImage: String, title: String, detail: String? = nil, tintHex: String? = nil,
                progress: Double? = nil, timerEnd: Date? = nil, timerStart: Date? = nil, duration: TimeInterval? = nil,
                buttons: [VehlaNotchActivityButton] = []) {
        self.id = id
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.tintHex = tintHex
        self.progress = progress
        self.timerEnd = timerEnd
        self.timerStart = timerStart
        self.duration = duration
        self.buttons = buttons
    }

    /// The dictionary sent to the host.
    public var info: [String: Any] {
        var info: [String: Any] = ["id": id, "symbol": systemImage, "title": title]
        if let detail { info["detail"] = detail }
        if let tintHex { info["tint"] = tintHex }
        if let progress { info["progress"] = min(1, max(0, progress)) }
        if let timerEnd { info["timerEnd"] = timerEnd }
        if let timerStart { info["timerStart"] = timerStart }
        if let duration { info["seconds"] = duration }
        if !buttons.isEmpty {
            info["buttons"] = buttons.prefix(2).map { button -> [String: String] in
                var entry = ["id": button.id, "title": button.title]
                if let symbol = button.systemImage { entry["symbol"] = symbol }
                return entry
            }
        }
        return info
    }
}

/// Typed access to the host. Make one in `notchDidStart` and keep it.
@MainActor
public final class VehlaNotch {
    public let host: any VehlaNotchHost

    public init(_ host: any VehlaNotchHost) { self.host = host }

    public var packageID: String { host.packageID }
    public var dataDirectory: URL { URL(fileURLWithPath: host.dataDirectoryPath, isDirectory: true) }
    public var accentColor: NSColor { host.themeInfo()["accent"] as? NSColor ?? .controlAccentColor }
    public func hasCapability(_ name: String) -> Bool { host.capabilities.contains(name) }

    /// Shows the activity, or updates the one already showing under that id.
    public func show(_ activity: VehlaNotchActivity) { host.showActivity(activity.info) }
    public func end(_ activityID: String) { host.endActivity(activityID) }
    public func openTab(_ tabID: String) { host.openTab(tabID) }

    @discardableResult public func open(_ url: URL) -> Bool { host.perform("openURL", info: ["url": url]) }
    @discardableResult public func copy(_ text: String) -> Bool { host.perform("copyText", info: ["text": text]) }
    public func log(_ message: String) { _ = host.perform("log", info: ["message": message]) }
    public func secret(named id: String) -> String? { host.secret(named: id) }
}
