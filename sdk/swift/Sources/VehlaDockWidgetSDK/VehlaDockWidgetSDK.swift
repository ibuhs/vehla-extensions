import AppKit
import Foundation

/// The plugin contract version implemented by this SDK.
public let VehlaDockWidgetAPIVersion = 1

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

    private let secretLookup: (String) -> String?
    private let secretStore: ((String, String) throws -> Void)?
    private let secretRemove: ((String) throws -> Void)?
    private let invalidationHandler: () -> Void
    private let actionHandler: (VehlaDockWidgetAction) -> Void

    @nonobjc
    public init(
        packageID: String,
        widgetID: String,
        dataDirectory: URL,
        theme: VehlaDockWidgetTheme,
        clipboard: VehlaDockWidgetClipboardBridge? = nil,
        localAI: VehlaDockWidgetLocalAIBridge? = nil,
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
        self.secretLookup = secretLookup
        self.secretStore = secretStore
        self.secretRemove = secretRemove
        self.invalidationHandler = invalidationHandler
        self.actionHandler = actionHandler
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
}
