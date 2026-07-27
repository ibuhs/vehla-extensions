import Foundation

enum ToolCategory: String, CaseIterable, Identifiable, Sendable {
    case json = "JSON / Data"
    case encoding = "Encoding"
    case crypto = "Cryptography"
    case date = "Date & Time"
    case text = "Text"
    case code = "Code"
    case sql = "SQL & Database"
    case generators = "Generators"
    case web = "Web Dev"
    case networking = "Networking"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .json: "curlybraces"
        case .encoding: "arrow.left.arrow.right"
        case .crypto: "lock.shield"
        case .date: "calendar"
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .sql: "cylinder.split.1x2"
        case .generators: "wand.and.stars"
        case .web: "globe"
        case .networking: "network"
        }
    }
}

enum ToolStatus: String, Sendable {
    case ready
    case stub
}

enum ToolInputKind: String, Sendable {
    case singleText
    case dualText
    case textAndOptions
    case none
}

struct ToolDefinition: Identifiable, Hashable, Sendable {
    let id: String
    let category: ToolCategory
    let title: String
    let subtitle: String
    let systemImage: String
    let status: ToolStatus
    let inputKind: ToolInputKind
    let primaryLabel: String
    let secondaryLabel: String?
    let optionKeys: [String]
    let stubReason: String?

    init(
        id: String,
        category: ToolCategory,
        title: String,
        subtitle: String,
        systemImage: String,
        status: ToolStatus = .ready,
        inputKind: ToolInputKind = .singleText,
        primaryLabel: String = "Input",
        secondaryLabel: String? = nil,
        optionKeys: [String] = [],
        stubReason: String? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.status = status
        self.inputKind = inputKind
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.optionKeys = optionKeys
        self.stubReason = stubReason
    }

    /// Whether the workbench should show the primary text editor.
    var showsPrimaryEditor: Bool {
        guard inputKind != .none else { return false }
        let label = primaryLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return false }
        let lower = label.lowercased()
        if lower == "unused" || lower.hasPrefix("ignored") { return false }
        return true
    }

    var showsSecondaryEditor: Bool {
        inputKind == .dualText && secondaryLabel != nil
    }
}

struct ToolRequest: Sendable {
    let toolID: String
    let primary: String
    let secondary: String
    let options: [String: String]
}

struct ToolOutput: Sendable {
    let text: String
    let meta: String?
    /// When set, the workbench shows a WKWebView preview of this HTML.
    let previewHTML: String?

    init(_ text: String, meta: String? = nil, previewHTML: String? = nil) {
        self.text = text
        self.meta = meta
        self.previewHTML = previewHTML
    }
}

enum ToolError: LocalizedError, Sendable {
    case unknownTool(String)
    case stub(String)
    case invalidInput(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownTool(let id): "Unknown tool: \(id)"
        case .stub(let reason): reason
        case .invalidInput(let message): message
        case .failed(let message): message
        }
    }
}

enum ToolLimits {
    static let maxInputBytes = 8 * 1_024 * 1_024
    static let maxOutputChars = 2_000_000

    static func guardSize(_ text: String, label: String = "Input") throws {
        let bytes = text.utf8.count
        guard bytes <= maxInputBytes else {
            throw ToolError.invalidInput(
                "\(label) is \(bytes) bytes; limit is \(maxInputBytes) bytes."
            )
        }
    }

    static func truncate(_ text: String) -> String {
        guard text.count > maxOutputChars else { return text }
        let index = text.index(text.startIndex, offsetBy: maxOutputChars)
        return String(text[..<index]) + "\n\n… truncated …"
    }
}
