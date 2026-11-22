// Dock Widget SDK, from Vehla Extensions: https://github.com/ibuhs/vehla-extensions
// Copyright (c) 2026 Shubham Kaila. Used under the MIT License; see THIRD_PARTY_NOTICES.md.

import AppKit
import Foundation

/// The plugin contract version implemented by this SDK.
///
/// Version 3 is additive: everything from version 2 is unchanged, so widgets built against version 2 keep
/// working. It adds declarative settings, tile badges, context-menu actions, host-managed scheduling, popup
/// control, logging and enforced capabilities. See docs/dock-widget-sdk.md.
public let VehlaDockWidgetAPIVersion = 3

@objc(VehlaDockWidgetSurface)
public enum VehlaDockWidgetSurface: Int, CaseIterable, Sendable {
    case compact
    case inline
    case popup
}

@objc(VehlaDockWidgetVisibilityPhase)
public enum VehlaDockWidgetVisibilityPhase: Int, Sendable {
    case hidden
    case compact
    case inline
    case popup
}

@objc(VehlaDockWidgetDescriptor)
@objcMembers
public final class VehlaDockWidgetDescriptor: NSObject {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let preferredPopupWidth: Double
    public let preferredPopupHeight: Double

    /// Objective-C-compatible raw values from ``VehlaDockWidgetSurface``.
    public let supportedSurfaceValues: [NSNumber]

    @nonobjc
    public var supportedSurfaces: [VehlaDockWidgetSurface] {
        supportedSurfaceValues.compactMap {
            VehlaDockWidgetSurface(rawValue: $0.intValue)
        }
    }

    @nonobjc
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String = "shippingbox",
        preferredPopupWidth: Double = 420,
        preferredPopupHeight: Double = 520,
        supportedSurfaces: [VehlaDockWidgetSurface] = [.compact]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.preferredPopupWidth = preferredPopupWidth
        self.preferredPopupHeight = preferredPopupHeight
        supportedSurfaceValues = supportedSurfaces.map {
            NSNumber(value: $0.rawValue)
        }
    }

    public init(
        id: String,
        title: String,
        subtitle: String?,
        systemImage: String,
        preferredPopupWidth: Double,
        preferredPopupHeight: Double,
        supportedSurfaceValues: [NSNumber]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.preferredPopupWidth = preferredPopupWidth
        self.preferredPopupHeight = preferredPopupHeight
        self.supportedSurfaceValues = supportedSurfaceValues
    }

    public func supportsSurface(_ surface: VehlaDockWidgetSurface) -> Bool {
        supportedSurfaceValues.contains {
            $0.intValue == surface.rawValue
        }
    }

    // Added in API 3. New stored properties stay last so the layout widgets built earlier rely on is unchanged.
    /// Settings the host shows for this widget under Settings → Dock Bar.
    public internal(set) var settingDescriptors: [VehlaDockWidgetSettingDescriptor] = []
    /// Entries in the tile's right-click menu.
    public internal(set) var menuActions: [VehlaDockWidgetMenuAction] = []
    /// The width of the wide (inline) tile, in points.
    public internal(set) var preferredInlineWidth: Double = 240
}

extension VehlaDockWidgetDescriptor {
    /// A descriptor with settings, menu actions and a wide-tile width (API 3).
    @nonobjc
    public convenience init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String = "shippingbox",
        preferredPopupWidth: Double = 420,
        preferredPopupHeight: Double = 520,
        supportedSurfaces: [VehlaDockWidgetSurface] = [.compact],
        settings: [VehlaDockWidgetSettingDescriptor],
        menuActions: [VehlaDockWidgetMenuAction] = [],
        preferredInlineWidth: Double = 240
    ) {
        self.init(
            id: id, title: title, subtitle: subtitle, systemImage: systemImage,
            preferredPopupWidth: preferredPopupWidth, preferredPopupHeight: preferredPopupHeight,
            supportedSurfaces: supportedSurfaces
        )
        settingDescriptors = settings
        self.menuActions = menuActions
        self.preferredInlineWidth = preferredInlineWidth
    }
}

// MARK: - API 3: settings, menu actions, scheduling

@objc(VehlaDockWidgetSettingKind)
public enum VehlaDockWidgetSettingKind: Int, Sendable {
    case toggle
    case choice
    case text
    case number
}

/// One setting a widget declares. The host draws the control, stores the value, and passes it back
/// through ``VehlaDockWidgetContext/settings``.
@objc(VehlaDockWidgetSettingDescriptor)
@objcMembers
public final class VehlaDockWidgetSettingDescriptor: NSObject {
    public let key: String
    public let title: String
    public let detail: String?
    public let kindRawValue: Int
    /// The default, as text: "true"/"false", a choice id, a string, or a number.
    public let defaultValue: String
    public let choiceIDs: [String]
    public let choiceTitles: [String]
    public let minimum: Double
    public let maximum: Double

    @nonobjc
    public var kind: VehlaDockWidgetSettingKind { VehlaDockWidgetSettingKind(rawValue: kindRawValue) ?? .text }

    private init(key: String, title: String, detail: String?, kind: VehlaDockWidgetSettingKind, defaultValue: String,
                 choiceIDs: [String] = [], choiceTitles: [String] = [], minimum: Double = 0, maximum: Double = 100) {
        self.key = key
        self.title = title
        self.detail = detail
        kindRawValue = kind.rawValue
        self.defaultValue = defaultValue
        self.choiceIDs = choiceIDs
        self.choiceTitles = choiceTitles
        self.minimum = minimum
        self.maximum = maximum
    }

    @nonobjc
    public static func toggle(key: String, title: String, detail: String? = nil, defaultValue: Bool = false) -> VehlaDockWidgetSettingDescriptor {
        .init(key: key, title: title, detail: detail, kind: .toggle, defaultValue: defaultValue ? "true" : "false")
    }

    @nonobjc
    public static func choice(key: String, title: String, detail: String? = nil, choices: [(id: String, title: String)],
                              defaultID: String) -> VehlaDockWidgetSettingDescriptor {
        .init(key: key, title: title, detail: detail, kind: .choice, defaultValue: defaultID,
              choiceIDs: choices.map(\.id), choiceTitles: choices.map(\.title))
    }

    @nonobjc
    public static func text(key: String, title: String, detail: String? = nil, defaultValue: String = "") -> VehlaDockWidgetSettingDescriptor {
        .init(key: key, title: title, detail: detail, kind: .text, defaultValue: defaultValue)
    }

    @nonobjc
    public static func number(key: String, title: String, detail: String? = nil, range: ClosedRange<Double>,
                              defaultValue: Double) -> VehlaDockWidgetSettingDescriptor {
        .init(key: key, title: title, detail: detail, kind: .number, defaultValue: String(defaultValue),
              minimum: range.lowerBound, maximum: range.upperBound)
    }
}

/// The current values of a widget's settings.
@objc(VehlaDockWidgetSettings)
@objcMembers
public final class VehlaDockWidgetSettings: NSObject {
    private var values: [String: String]
    private let defaults: [String: String]

    public override init() {
        values = [:]
        defaults = [:]
    }

    @nonobjc
    public init(descriptors: [VehlaDockWidgetSettingDescriptor], stored: [String: String]) {
        defaults = Dictionary(descriptors.map { ($0.key, $0.defaultValue) }, uniquingKeysWith: { first, _ in first })
        values = stored
    }

    public func string(_ key: String) -> String? { values[key] ?? defaults[key] }
    public func bool(_ key: String) -> Bool { string(key) == "true" }
    public func double(_ key: String) -> Double { string(key).flatMap(Double.init) ?? 0 }

    /// Called by the host when a value changes.
    public func update(_ key: String, to value: String) { values[key] = value }
}

@objc(VehlaDockWidgetMenuAction)
@objcMembers
public final class VehlaDockWidgetMenuAction: NSObject {
    public let id: String
    public let title: String
    public let systemImage: String?

    public init(id: String, title: String, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

@objc(VehlaDockWidgetLogLevel)
public enum VehlaDockWidgetLogLevel: Int, Sendable {
    case info
    case warning
    case error
}

/// A repeating task owned by the host's visibility rules.
@objc(VehlaDockWidgetScheduledTask)
@objcMembers
@MainActor
public final class VehlaDockWidgetScheduledTask: NSObject {
    fileprivate let interval: TimeInterval
    fileprivate let runWhileHidden: Bool
    fileprivate let handler: @MainActor () -> Void
    fileprivate var timer: Timer?
    fileprivate var cancelled = false

    fileprivate init(interval: TimeInterval, runWhileHidden: Bool, handler: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.runWhileHidden = runWhileHidden
        self.handler = handler
    }

    public func cancel() {
        cancelled = true
        timer?.invalidate()
        timer = nil
    }
}

@objc(VehlaDockWidgetTheme)
@objcMembers
public final class VehlaDockWidgetTheme: NSObject {
    public let isDark: Bool
    public let accentColor: NSColor
    public let primaryTextColor: NSColor
    public let secondaryTextColor: NSColor
    /// Host-resolved foreground for compact and inline Dock tile surfaces.
    public let tileTextColor: NSColor
    public let surfaceColor: NSColor
    public let separatorColor: NSColor

    public init(
        isDark: Bool,
        accentColor: NSColor,
        primaryTextColor: NSColor,
        secondaryTextColor: NSColor,
        surfaceColor: NSColor,
        separatorColor: NSColor = .separatorColor
    ) {
        self.isDark = isDark
        self.accentColor = accentColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.tileTextColor = primaryTextColor
        self.surfaceColor = surfaceColor
        self.separatorColor = separatorColor
    }

    public init(
        isDark: Bool,
        accentColor: NSColor,
        primaryTextColor: NSColor,
        secondaryTextColor: NSColor,
        tileTextColor: NSColor,
        surfaceColor: NSColor,
        separatorColor: NSColor = .separatorColor
    ) {
        self.isDark = isDark
        self.accentColor = accentColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.tileTextColor = tileTextColor
        self.surfaceColor = surfaceColor
        self.separatorColor = separatorColor
    }
}

public enum VehlaDockWidgetAction: Sendable {
    case copyText(String)
    case openURL(URL)
    case showMessage(String)
    case notify(title: String, body: String)
}

@objc(VehlaDockWidgetSharedContextKind)
public enum VehlaDockWidgetSharedContextKind: Int, Sendable {
    case event
    case reminder
    case media
    case weather
    case timer
    case metric
    case link
    case text
}

@objc(VehlaDockWidgetSharedContext)
@objcMembers
public final class VehlaDockWidgetSharedContext: NSObject {
    public let id: String
    public let kind: VehlaDockWidgetSharedContextKind
    public let sourceID: String
    public let title: String
    public let subtitle: String?
    public let body: String?
    public let url: URL?
    public let startDate: Date?
    public let endDate: Date?
    public let metadata: [String: String]

    public init(
        id: String,
        kind: VehlaDockWidgetSharedContextKind,
        sourceID: String,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        url: URL? = nil,
        startDate: Date? = nil,
        endDate: Date? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.sourceID = sourceID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.url = url
        self.startDate = startDate
        self.endDate = endDate
        self.metadata = metadata
    }
}

@objc(VehlaDockWidgetSharedAction)
public enum VehlaDockWidgetSharedAction: Int, Sendable {
    case askAI
    case addToNotes
    case createReminder
    case runSpeedTest
    case copyDetails
}

@objc(VehlaDockWidgetAppBridge)
@objcMembers
@MainActor
public final class VehlaDockWidgetAppBridge: NSObject {
    private let currentContextHandler: () -> VehlaDockWidgetSharedContext?
    private let publishHandler: (VehlaDockWidgetSharedContext) -> Bool
    private let actionHandler:
        (VehlaDockWidgetSharedAction, VehlaDockWidgetSharedContext) -> Bool
    private let timerHandler:
        (String?, TimeInterval, VehlaDockWidgetSharedContext?) -> Bool

    @nonobjc
    public init(
        currentContextHandler: @escaping () -> VehlaDockWidgetSharedContext?,
        publishHandler: @escaping (VehlaDockWidgetSharedContext) -> Bool,
        actionHandler: @escaping
            (VehlaDockWidgetSharedAction, VehlaDockWidgetSharedContext) -> Bool,
        timerHandler: @escaping
            (String?, TimeInterval, VehlaDockWidgetSharedContext?) -> Bool
    ) {
        self.currentContextHandler = currentContextHandler
        self.publishHandler = publishHandler
        self.actionHandler = actionHandler
        self.timerHandler = timerHandler
    }

    public var currentContext: VehlaDockWidgetSharedContext? {
        currentContextHandler()
    }

    @discardableResult
    public func publish(_ context: VehlaDockWidgetSharedContext) -> Bool {
        publishHandler(context)
    }

    @discardableResult
    public func perform(
        _ action: VehlaDockWidgetSharedAction,
        with context: VehlaDockWidgetSharedContext
    ) -> Bool {
        actionHandler(action, context)
    }

    @discardableResult
    public func startTimer(
        label: String?,
        duration: TimeInterval,
        context: VehlaDockWidgetSharedContext? = nil
    ) -> Bool {
        timerHandler(label, duration, context)
    }
}

public enum VehlaDockWidgetSecretError: LocalizedError, Sendable {
    case updatesUnavailable
    case removalUnavailable

    public var errorDescription: String? {
        switch self {
        case .updatesUnavailable:
            return "This Dock widget cannot update secrets."
        case .removalUnavailable:
            return "This Dock widget cannot remove secrets."
        }
    }
}

public enum VehlaDockWidgetAIMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct VehlaDockWidgetAIMessage: Codable, Hashable, Sendable {
    public let role: VehlaDockWidgetAIMessageRole
    public let content: String

    public init(role: VehlaDockWidgetAIMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

@objc(VehlaDockWidgetClipboardItemKind)
public enum VehlaDockWidgetClipboardItemKind: Int, Sendable {
    case text
    case url
    case image
}

@objc(VehlaDockWidgetClipboardItem)
@objcMembers
public final class VehlaDockWidgetClipboardItem: NSObject {
    public let id: String
    public let kindRawValue: Int
    public let text: String
    public let preview: String
    public let searchText: String
    public let imageFileURL: URL?
    public let createdAt: Date
    public let sourceAppName: String?
    public let isPinned: Bool

    @nonobjc
    public var kind: VehlaDockWidgetClipboardItemKind {
        VehlaDockWidgetClipboardItemKind(rawValue: kindRawValue) ?? .text
    }

    @nonobjc
    public init(
        id: String,
        kind: VehlaDockWidgetClipboardItemKind,
        text: String,
        preview: String,
        searchText: String,
        imageFileURL: URL?,
        createdAt: Date,
        sourceAppName: String?,
        isPinned: Bool
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.text = text
        self.preview = preview
        self.searchText = searchText
        self.imageFileURL = imageFileURL
        self.createdAt = createdAt
        self.sourceAppName = sourceAppName
        self.isPinned = isPinned
    }
}

/// Optional access to Vehla's canonical clipboard history. The host owns all
/// data and mutations; widgets should keep a local fallback for older hosts.
@objc(VehlaDockWidgetClipboardBridge)
@objcMembers
@MainActor
public final class VehlaDockWidgetClipboardBridge: NSObject {
    private let itemCountHandler: () -> Int
    private let itemsHandler: (Int, Int) -> [VehlaDockWidgetClipboardItem]
    private let restoreHandler: (String) -> Bool
    private let deleteHandler: (String) -> Void
    private let clearHandler: () -> Void
    private let pinHandler: (String, Bool) -> Bool
    private let activeViewerHandler: (Bool) -> Void

    @nonobjc
    public init(
        itemCountHandler: @escaping () -> Int,
        itemsHandler: @escaping (Int, Int) -> [VehlaDockWidgetClipboardItem],
        restoreHandler: @escaping (String) -> Bool,
        deleteHandler: @escaping (String) -> Void,
        clearHandler: @escaping () -> Void,
        pinHandler: @escaping (String, Bool) -> Bool,
        activeViewerHandler: @escaping (Bool) -> Void
    ) {
        self.itemCountHandler = itemCountHandler
        self.itemsHandler = itemsHandler
        self.restoreHandler = restoreHandler
        self.deleteHandler = deleteHandler
        self.clearHandler = clearHandler
        self.pinHandler = pinHandler
        self.activeViewerHandler = activeViewerHandler
    }

    public var totalItemCount: Int {
        itemCountHandler()
    }

    public func items(
        offset: Int,
        limit: Int
    ) -> [VehlaDockWidgetClipboardItem] {
        guard offset >= 0, limit > 0 else { return [] }
        return itemsHandler(offset, limit)
    }

    public func restoreItem(id: String) -> Bool {
        restoreHandler(id)
    }

    public func deleteItem(id: String) {
        deleteHandler(id)
    }

    public func clearHistory() {
        clearHandler()
    }

    public func setPinned(_ pinned: Bool, itemID: String) -> Bool {
        pinHandler(itemID, pinned)
    }

    public func setActiveViewer(_ active: Bool) {
        activeViewerHandler(active)
    }
}

/// Brokered access to Vehla's selected, downloaded on-device MLX model.
///
/// The host owns model selection, loading, and inference. Widgets receive
/// text-only completion access and never link MLX or inspect model files.
@objc(VehlaDockWidgetLocalAIBridge)
@objcMembers
@MainActor
public final class VehlaDockWidgetLocalAIBridge: NSObject {
    private let availabilityHandler: () -> Bool
    private let statusHandler: () -> String
    private let completionHandler:
        ([VehlaDockWidgetAIMessage]) async throws -> String

    @nonobjc
    public init(
        availabilityHandler: @escaping () -> Bool,
        statusHandler: @escaping () -> String,
        completionHandler: @escaping
            ([VehlaDockWidgetAIMessage]) async throws -> String
    ) {
        self.availabilityHandler = availabilityHandler
        self.statusHandler = statusHandler
        self.completionHandler = completionHandler
    }

    public var isAvailable: Bool {
        availabilityHandler()
    }

    public var statusLabel: String {
        statusHandler()
    }

    @nonobjc
    public func complete(
        messages: [VehlaDockWidgetAIMessage]
    ) async throws -> String {
        try await completionHandler(messages)
    }
}

@objc(VehlaDockWidgetContext)
@objcMembers
public final class VehlaDockWidgetContext: NSObject {
    public let packageID: String
    public let widgetID: String
    public let dataDirectory: URL
    public let theme: VehlaDockWidgetTheme
    public let clipboard: VehlaDockWidgetClipboardBridge?
    public let localAI: VehlaDockWidgetLocalAIBridge?
    public let app: VehlaDockWidgetAppBridge?

    private let secretLookup: (String) -> String?
    private let secretStore: ((String, String) throws -> Void)?
    private let secretRemove: ((String) throws -> Void)?
    private let invalidationHandler: () -> Void
    private let actionHandler: (VehlaDockWidgetAction) -> Void

    // Added in API 3, last, so the layout widgets built earlier rely on is unchanged.
    /// The widget's settings and their current values (API 3).
    public private(set) var settings = VehlaDockWidgetSettings()
    /// What the host allows this widget to do, from its manifest (API 3).
    public private(set) var capabilities: Set<String> = []
    @MainActor private var tasks: [VehlaDockWidgetScheduledTask] = []
    @MainActor private var isVisible = false
    private var badgeHandler: ((String?, NSColor?) -> Void)?
    private var popupHandler: ((Bool) -> Void)?
    private var logHandler: ((String, VehlaDockWidgetLogLevel) -> Void)?

    @nonobjc
    public init(
        packageID: String,
        widgetID: String,
        dataDirectory: URL,
        theme: VehlaDockWidgetTheme,
        clipboard: VehlaDockWidgetClipboardBridge? = nil,
        localAI: VehlaDockWidgetLocalAIBridge? = nil,
        app: VehlaDockWidgetAppBridge? = nil,
        secretLookup: @escaping (String) -> String? = { _ in nil },
        secretStore: ((String, String) throws -> Void)? = nil,
        secretRemove: ((String) throws -> Void)? = nil,
        invalidationHandler: @escaping () -> Void,
        actionHandler: @escaping (VehlaDockWidgetAction) -> Void
    ) {
        self.packageID = packageID
        self.widgetID = widgetID
        self.dataDirectory = dataDirectory
        self.theme = theme
        self.clipboard = clipboard
        self.localAI = localAI
        self.app = app
        self.secretLookup = secretLookup
        self.secretStore = secretStore
        self.secretRemove = secretRemove
        self.invalidationHandler = invalidationHandler
        self.actionHandler = actionHandler
    }

    /// Called by the host after creating the context (API 3).
    @nonobjc
    public func attachHost(
        settings: VehlaDockWidgetSettings,
        capabilities: Set<String>,
        badge: @escaping (String?, NSColor?) -> Void,
        popup: @escaping (Bool) -> Void,
        log: @escaping (String, VehlaDockWidgetLogLevel) -> Void
    ) {
        self.settings = settings
        self.capabilities = capabilities
        badgeHandler = badge
        popupHandler = popup
        logHandler = log
    }

    /// Whether this widget's manifest declared the capability (API 3).
    public func hasCapability(_ name: String) -> Bool { capabilities.contains(name) }

    /// Shows a short badge on the widget's tile, such as an unread count; nil clears it (API 3).
    public func setBadge(_ text: String?, tint: NSColor? = nil) { badgeHandler?(text, tint) }

    /// Opens the widget's popup, for example to show an alert (API 3).
    public func showPopup() { popupHandler?(true) }

    /// Closes the widget's popup (API 3).
    public func closePopup() { popupHandler?(false) }

    /// Writes to the host's log under the widget's name (API 3).
    public func log(_ message: String, level: VehlaDockWidgetLogLevel = .info) { logHandler?(message, level) }

    /// Runs `handler` every `interval` seconds while the widget is visible, and pauses it while hidden, so widgets
    /// do no background work nobody can see (API 3). Cancel the returned task, or let the widget close, to stop it.
    @MainActor
    @discardableResult
    public func schedule(
        every interval: TimeInterval,
        runWhileHidden: Bool = false,
        _ handler: @escaping @MainActor () -> Void
    ) -> VehlaDockWidgetScheduledTask {
        let task = VehlaDockWidgetScheduledTask(interval: max(0.05, interval), runWhileHidden: runWhileHidden, handler: handler)
        tasks.append(task)
        if isVisible || runWhileHidden { start(task) }
        return task
    }

    @MainActor
    private func start(_ task: VehlaDockWidgetScheduledTask) {
        guard task.timer == nil, !task.cancelled else { return }
        task.timer = Timer.scheduledTimer(withTimeInterval: task.interval, repeats: true) { _ in
            MainActor.assumeIsolated { task.handler() }
        }
        task.timer?.tolerance = task.interval * 0.1
    }

    /// Called by the host when the widget becomes visible or hidden (API 3).
    @MainActor
    public func hostVisibilityChanged(_ visible: Bool) {
        isVisible = visible
        tasks.removeAll { $0.cancelled }
        for task in tasks {
            if visible || task.runWhileHidden { start(task) } else { task.timer?.invalidate(); task.timer = nil }
        }
    }

    /// Stops every scheduled task (API 3). The host calls this when the widget closes.
    @MainActor
    public func hostStopScheduledTasks() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    /// Returns a Keychain-backed value declared by this package's manifest.
    public func secret(named id: String) -> String? {
        secretLookup(id)
    }

    /// Stores a Keychain-backed value declared by this package's manifest.
    public func setSecret(_ value: String, named id: String) throws {
        guard let secretStore else {
            throw VehlaDockWidgetSecretError.updatesUnavailable
        }
        try secretStore(id, value)
    }

    /// Removes a Keychain-backed value declared by this package's manifest.
    public func removeSecret(named id: String) throws {
        guard let secretRemove else {
            throw VehlaDockWidgetSecretError.removalUnavailable
        }
        try secretRemove(id)
    }

    /// Asks Vehla to refresh the widget's currently visible surfaces.
    public func invalidate() {
        invalidationHandler()
    }

    public func copyText(_ text: String) {
        actionHandler(.copyText(text))
    }

    public func open(_ url: URL) {
        actionHandler(.openURL(url))
    }

    public func showMessage(_ message: String) {
        actionHandler(.showMessage(message))
    }

    public func notify(title: String, body: String) {
        actionHandler(.notify(title: title, body: body))
    }
}

/// Implemented by the principal class of a trusted in-process widget bundle.
///
/// Lifecycle callbacks are synchronous notifications and must return
/// immediately. Start asynchronous work in cancellable `Task`s owned by an
/// actor, and cancel those tasks when the widget becomes hidden or closes.
@objc(VehlaDockWidgetPlugin)
public protocol VehlaDockWidgetPlugin: NSObjectProtocol {
    var apiVersion: Int { get }
    var widgets: [VehlaDockWidgetDescriptor] { get }

    @MainActor
    func makeViewController(
        widgetID: String,
        surface: VehlaDockWidgetSurface,
        context: VehlaDockWidgetContext
    ) throws -> NSViewController

    /// A nonblocking visibility notification; do not perform work inline.
    @MainActor
    @objc optional func widget(
        _ widgetID: String,
        didEnter phase: VehlaDockWidgetVisibilityPhase
    )

    /// A nonblocking theme notification; update UI and schedule work only.
    @MainActor
    @objc optional func widget(
        _ widgetID: String,
        themeDidChange theme: VehlaDockWidgetTheme
    )

    /// The final nonblocking notification for this widget instance.
    @MainActor
    @objc optional func widgetWillClose(_ widgetID: String)

    /// A setting declared in the descriptor changed (API 3). Read the new value from `context.settings`.
    @MainActor
    @objc optional func widget(_ widgetID: String, settingDidChange key: String)

    /// The user chose one of the descriptor's menu actions on the tile (API 3).
    @MainActor
    @objc optional func widget(_ widgetID: String, performAction actionID: String)
}
