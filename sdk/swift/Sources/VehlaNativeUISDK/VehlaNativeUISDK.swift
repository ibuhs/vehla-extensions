import AppKit
import Foundation

public let VehlaNativeUIAPIVersion = 1

@objc(VehlaWorkspaceDismissBehavior)
public enum VehlaWorkspaceDismissBehavior: Int, Sendable {
    case persistent
    case dismissOnResignKey
}

@objc(VehlaWorkspaceDescriptor)
@objcMembers
public final class VehlaWorkspaceDescriptor: NSObject {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let systemImage: String
    public let preferredWidth: Double
    public let preferredHeight: Double
    public let minimumWidth: Double
    public let minimumHeight: Double
    public let dismissBehavior: VehlaWorkspaceDismissBehavior

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String = "shippingbox",
        preferredWidth: Double = 1_180,
        preferredHeight: Double = 760,
        minimumWidth: Double = 760,
        minimumHeight: Double = 560,
        dismissBehavior: VehlaWorkspaceDismissBehavior = .persistent
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.minimumWidth = minimumWidth
        self.minimumHeight = minimumHeight
        self.dismissBehavior = dismissBehavior
    }
}

@objc(VehlaWorkspaceLaunchRequest)
@objcMembers
public final class VehlaWorkspaceLaunchRequest: NSObject {
    public let commandID: String?
    public let query: String
    public let payload: [String: String]

    public init(
        commandID: String? = nil,
        query: String = "",
        payload: [String: String] = [:]
    ) {
        self.commandID = commandID
        self.query = query
        self.payload = payload
    }
}

@objc(VehlaWorkspaceTheme)
@objcMembers
public final class VehlaWorkspaceTheme: NSObject {
    public let isDark: Bool
    public let accentColor: NSColor
    public let primaryTextColor: NSColor
    public let secondaryTextColor: NSColor
    public let backgroundColor: NSColor
    public let surfaceColor: NSColor

    public init(
        isDark: Bool,
        accentColor: NSColor,
        primaryTextColor: NSColor,
        secondaryTextColor: NSColor,
        surfaceColor: NSColor,
        backgroundColor: NSColor? = nil
    ) {
        self.isDark = isDark
        self.accentColor = accentColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.backgroundColor = backgroundColor ?? surfaceColor
        self.surfaceColor = surfaceColor
    }
}

public enum VehlaWorkspaceAIMessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

public struct VehlaWorkspaceAIMessage: Codable, Hashable, Sendable {
    public let role: VehlaWorkspaceAIMessageRole
    public let content: String

    public init(role: VehlaWorkspaceAIMessageRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// Brokered access to Vehla's selected, downloaded on-device MLX model.
///
/// The host owns model selection, loading, and inference. Workspaces receive
/// text-only completion access and never link MLX or inspect model files.
@objc(VehlaWorkspaceLocalAIBridge)
@objcMembers
@MainActor
public final class VehlaWorkspaceLocalAIBridge: NSObject {
    private let availabilityHandler: () -> Bool
    private let statusHandler: () -> String
    private let completionHandler:
        ([VehlaWorkspaceAIMessage]) async throws -> String

    @nonobjc
    public init(
        availabilityHandler: @escaping () -> Bool,
        statusHandler: @escaping () -> String,
        completionHandler: @escaping
            ([VehlaWorkspaceAIMessage]) async throws -> String
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
        messages: [VehlaWorkspaceAIMessage]
    ) async throws -> String {
        try await completionHandler(messages)
    }
}

public enum VehlaWorkspaceAction: Sendable {
    case copyText(String)
    case openURL(URL)
    case showMessage(String)
    case notify(title: String, body: String)
    case openWorkspace(id: String, query: String)
}

@objc(VehlaWorkspaceContext)
@objcMembers
public final class VehlaWorkspaceContext: NSObject {
    public let packageID: String
    public let workspaceID: String
    public let dataDirectory: URL
    public let launchRequest: VehlaWorkspaceLaunchRequest
    public let theme: VehlaWorkspaceTheme
    public let localAI: VehlaWorkspaceLocalAIBridge?

    private let secretLookup: (String) -> String?
    private let secretStore: ((String, String) throws -> Void)?
    private let secretRemove: ((String) throws -> Void)?
    private let actionHandler: (VehlaWorkspaceAction) -> Void

    public init(
        packageID: String,
        workspaceID: String,
        dataDirectory: URL,
        launchRequest: VehlaWorkspaceLaunchRequest,
        theme: VehlaWorkspaceTheme,
        localAI: VehlaWorkspaceLocalAIBridge? = nil,
        secretLookup: @escaping (String) -> String?,
        secretStore: ((String, String) throws -> Void)? = nil,
        secretRemove: ((String) throws -> Void)? = nil,
        actionHandler: @escaping (VehlaWorkspaceAction) -> Void
    ) {
        self.packageID = packageID
        self.workspaceID = workspaceID
        self.dataDirectory = dataDirectory
        self.launchRequest = launchRequest
        self.theme = theme
        self.localAI = localAI
        self.secretLookup = secretLookup
        self.secretStore = secretStore
        self.secretRemove = secretRemove
        self.actionHandler = actionHandler
    }

    public func secret(named id: String) -> String? {
        secretLookup(id)
    }

    public func setSecret(_ value: String, named id: String) throws {
        guard let secretStore else {
            throw NSError(
                domain: "VehlaNativeUISDK",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This workspace cannot update secrets."
                ]
            )
        }
        try secretStore(id, value)
    }

    public func removeSecret(named id: String) throws {
        guard let secretRemove else {
            throw NSError(
                domain: "VehlaNativeUISDK",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This workspace cannot remove secrets."
                ]
            )
        }
        try secretRemove(id)
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

    public func openWorkspace(id: String, query: String = "") {
        actionHandler(.openWorkspace(id: id, query: query))
    }
}

@objc(VehlaNativeWorkspacePlugin)
public protocol VehlaNativeWorkspacePlugin: NSObjectProtocol {
    var apiVersion: Int { get }
    var workspaces: [VehlaWorkspaceDescriptor] { get }

    @MainActor
    func makeViewController(
        workspaceID: String,
        context: VehlaWorkspaceContext
    ) throws -> NSViewController

    /// A nonblocking theme notification; update UI and schedule work only.
    @MainActor
    @objc optional func workspace(
        _ workspaceID: String,
        themeDidChange theme: VehlaWorkspaceTheme
    )

    @MainActor
    @objc optional func workspaceWillClose(_ workspaceID: String)
}
