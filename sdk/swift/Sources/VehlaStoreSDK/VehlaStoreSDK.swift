import AppKit
import Darwin
import Foundation

public enum StoreCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case clipboardRead
    case clipboardWrite
    case openURL
    case notifications
    case selectedText
    case userSelectedFiles
    case networkAccess
    case persistentStorage
}

public struct StoreSelectedFile: Codable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let contentType: String?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        contentType: String? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.contentType = contentType
    }
}

public enum StoreFormValue: Codable, Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case file(StoreSelectedFile)
    case files([StoreSelectedFile])

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var fileValue: StoreSelectedFile? {
        guard case .file(let value) = self else { return nil }
        return value
    }

    public var filesValue: [StoreSelectedFile]? {
        switch self {
        case .file(let value): return [value]
        case .files(let value): return value
        default: return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(StoreSelectedFile.self) {
            self = .file(value)
        } else if let value = try? container.decode([StoreSelectedFile].self) {
            self = .files(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .file(let value): try container.encode(value)
        case .files(let value): try container.encode(value)
        }
    }
}

public struct StoreInvocationContext: Codable, Sendable {
    public let selectedText: String?
    public let clipboardText: String?
    public let frontmostApplication: String?
    public let dataDirectory: String?
    public let grantedCapabilities: [StoreCapability]
    public let secrets: [String: String]
    public let formValues: [String: StoreFormValue]

    public init(
        selectedText: String? = nil,
        clipboardText: String? = nil,
        frontmostApplication: String? = nil,
        dataDirectory: String? = nil,
        grantedCapabilities: [StoreCapability] = [],
        secrets: [String: String] = [:],
        formValues: [String: StoreFormValue] = [:]
    ) {
        self.selectedText = selectedText
        self.clipboardText = clipboardText
        self.frontmostApplication = frontmostApplication
        self.dataDirectory = dataDirectory
        self.grantedCapabilities = grantedCapabilities
        self.secrets = secrets
        self.formValues = formValues
    }

    private enum CodingKeys: String, CodingKey {
        case selectedText, clipboardText, frontmostApplication
        case dataDirectory, grantedCapabilities, secrets, formValues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedText = try container.decodeIfPresent(
            String.self,
            forKey: .selectedText
        )
        clipboardText = try container.decodeIfPresent(
            String.self,
            forKey: .clipboardText
        )
        frontmostApplication = try container.decodeIfPresent(
            String.self,
            forKey: .frontmostApplication
        )
        dataDirectory = try container.decodeIfPresent(
            String.self,
            forKey: .dataDirectory
        )
        grantedCapabilities = try container.decodeIfPresent(
            [StoreCapability].self,
            forKey: .grantedCapabilities
        ) ?? []
        secrets = try container.decodeIfPresent(
            [String: String].self,
            forKey: .secrets
        ) ?? [:]
        formValues = try container.decodeIfPresent(
            [String: StoreFormValue].self,
            forKey: .formValues
        ) ?? [:]
    }

    public func grants(_ capability: StoreCapability) -> Bool {
        grantedCapabilities.contains(capability)
    }
}

public struct StoreInvocation: Codable, Sendable {
    public let packageID: String
    public let commandID: String
    public let query: String
    public let context: StoreInvocationContext

    public init(
        packageID: String,
        commandID: String,
        query: String,
        context: StoreInvocationContext
    ) {
        self.packageID = packageID
        self.commandID = commandID
        self.query = query
        self.context = context
    }
}

public enum StoreActionKind: String, Codable, Sendable {
    case copyText
    case openURL
    case showMessage
    case notify
}

public struct StoreAction: Codable, Hashable, Sendable {
    public let type: StoreActionKind
    public let value: String
    public let title: String?
    public let label: String?
    public let systemImage: String?

    public init(
        type: StoreActionKind,
        value: String,
        title: String? = nil,
        label: String? = nil,
        systemImage: String? = nil
    ) {
        self.type = type
        self.value = value
        self.title = title
        self.label = label
        self.systemImage = systemImage
    }
}

public enum StoreRichItemKind: String, Codable, Sendable {
    case text
    case markdown
    case code
    case detail
}

public struct StoreRichItem: Codable, Hashable, Sendable {
    public let type: StoreRichItemKind
    public let text: String?
    public let label: String?
    public let value: String?
    public let language: String?

    public init(
        type: StoreRichItemKind,
        text: String? = nil,
        label: String? = nil,
        value: String? = nil,
        language: String? = nil
    ) {
        self.type = type
        self.text = text
        self.label = label
        self.value = value
        self.language = language
    }

    public static func text(_ value: String) -> Self {
        Self(type: .text, text: value)
    }

    public static func markdown(_ value: String) -> Self {
        Self(type: .markdown, text: value)
    }

    public static func code(_ value: String, language: String? = nil) -> Self {
        Self(type: .code, text: value, language: language)
    }

    public static func detail(_ label: String, value: String) -> Self {
        Self(type: .detail, label: label, value: value)
    }
}

public struct StoreRichSection: Codable, Hashable, Sendable {
    public let title: String?
    public let items: [StoreRichItem]

    public init(title: String? = nil, items: [StoreRichItem]) {
        self.title = title
        self.items = items
    }
}

public struct StoreRichView: Codable, Hashable, Sendable {
    public let title: String
    public let subtitle: String?
    public let sections: [StoreRichSection]
    public let actions: [StoreAction]

    public init(
        title: String,
        subtitle: String? = nil,
        sections: [StoreRichSection] = [],
        actions: [StoreAction] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sections = sections
        self.actions = actions
    }
}

public struct StoreResult: Codable, Hashable, Sendable {
    public let message: String?
    public let action: StoreAction?
    public let view: StoreRichView?

    public init(
        message: String? = nil,
        action: StoreAction? = nil,
        view: StoreRichView? = nil
    ) {
        self.message = message
        self.action = action
        self.view = view
    }
}

public enum Store {
    public static func copyText(_ value: String) -> StoreResult {
        StoreResult(action: StoreAction(type: .copyText, value: value))
    }

    public static func openURL(_ value: String) -> StoreResult {
        StoreResult(action: StoreAction(type: .openURL, value: value))
    }

    public static func showMessage(_ value: String) -> StoreResult {
        StoreResult(action: StoreAction(type: .showMessage, value: value))
    }

    public static func notify(title: String, body: String) -> StoreResult {
        StoreResult(
            action: StoreAction(type: .notify, value: body, title: title)
        )
    }

    public static func view(_ value: StoreRichView) -> StoreResult {
        StoreResult(view: value)
    }
}

public typealias StoreCommandHandler = @Sendable (
    StoreInvocation
) async throws -> StoreResult?

private struct StoreRequest: Decodable {
    let jsonrpc: String
    let id: String
    let method: String
    let params: StoreInvocation
}

private struct StoreFailure: Encodable {
    let code: Int
    let message: String
}

private struct StoreResponse: Encodable {
    let jsonrpc = "2.0"
    let id: String?
    let result: StoreResult?
    let error: StoreFailure?
}

public func runStoreExtension(
    _ handler: @escaping StoreCommandHandler
) async {
    await MainActor.run {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
    }
    _ = Darwin.signal(SIGPIPE, SIG_IGN)
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    while let line = readLine() {
        var responseID: String?
        let response: StoreResponse
        do {
            let request = try decoder.decode(
                StoreRequest.self,
                from: Data(line.utf8)
            )
            responseID = request.id
            guard request.jsonrpc == "2.0",
                  request.method == "store.invoke" else {
                throw StoreSDKError.unsupportedRequest
            }
            let result = try await handler(request.params) ?? StoreResult()
            response = StoreResponse(
                id: request.id,
                result: result,
                error: nil
            )
        } catch {
            response = StoreResponse(
                id: responseID,
                result: nil,
                error: StoreFailure(
                    code: -32000,
                    message: error.localizedDescription
                )
            )
        }

        guard let data = try? encoder.encode(response) else {
            continue
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}

private enum StoreSDKError: LocalizedError {
    case unsupportedRequest

    var errorDescription: String? {
        switch self {
        case .unsupportedRequest:
            return "Unsupported Store request."
        }
    }
}
