import Foundation
import VehlaNativeUISDK

struct QuickGlassActionDefinition: Sendable {
    let id: String
    let title: String
    let systemImage: String
    let delivery: VehlaWorkspaceQuickGlassDelivery
    let toolID: String
    let optionOverrides: [String: String]

    init(
        _ id: String,
        _ title: String,
        _ systemImage: String,
        delivery: VehlaWorkspaceQuickGlassDelivery = .replaceSelection,
        toolID: String,
        options: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.delivery = delivery
        self.toolID = toolID
        optionOverrides = options
    }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: id,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }

    func request(selectedText: String) throws -> ToolRequest {
        guard let tool = ToolCatalog.tool(id: toolID), tool.status == .ready else {
            throw ToolError.unknownTool(toolID)
        }
        return ToolRequest(
            toolID: toolID,
            primary: selectedText,
            secondary: "",
            options: ToolOptionDefaults.options(for: tool, overrides: optionOverrides)
        )
    }
}

enum QuickGlassActionCatalog {
    static let all: [QuickGlassActionDefinition] = [
        .init("json.format", "Format JSON", "text.alignleft", toolID: "json.formatter"),
        .init("json.minify", "Minify JSON", "arrow.down.right.and.arrow.up.left", toolID: "json.minifier"),
        .init("json.validate", "Validate JSON", "checkmark.seal", delivery: .compactResult, toolID: "json.validator"),

        .init("base64.encode", "Base64 Encode", "b.square", toolID: "enc.base64", options: ["mode": "encode"]),
        .init("base64.decode", "Base64 Decode", "b.square.fill", toolID: "enc.base64", options: ["mode": "decode"]),
        .init("url.encode", "URL Encode", "link", toolID: "enc.url", options: ["mode": "encode"]),
        .init("url.decode", "URL Decode", "link.badge.plus", toolID: "enc.url", options: ["mode": "decode"]),
        .init("html.encode", "HTML Encode", "chevron.left.forwardslash.chevron.right", toolID: "enc.html", options: ["mode": "encode"]),
        .init("html.decode", "HTML Decode", "chevron.left.slash.chevron.right", toolID: "enc.html", options: ["mode": "decode"]),
        .init("hex.encode", "Text to Hex", "number", toolID: "enc.hex", options: ["mode": "encode"]),
        .init("hex.decode", "Hex to Text", "number.square", toolID: "enc.hex", options: ["mode": "decode"]),
        .init("rot13", "ROT13", "arrow.2.squarepath", toolID: "enc.rot13"),

        .init("hash.sha1", "SHA-1", "number", delivery: .compactResult, toolID: "crypto.sha1"),
        .init("hash.sha256", "SHA-256", "number", delivery: .compactResult, toolID: "crypto.sha256"),
        .init("hash.sha512", "SHA-512", "number", delivery: .compactResult, toolID: "crypto.sha512"),
        .init("hash.sha3-256", "SHA3-256", "number", delivery: .compactResult, toolID: "crypto.sha3"),
        .init("hash.md5", "MD5", "exclamationmark.lock", delivery: .compactResult, toolID: "crypto.md5"),

        .init("date.unix-to-iso", "Unix to ISO 8601", "clock", delivery: .compactResult, toolID: "date.unix", options: ["mode": "to-date"]),
        .init("date.iso-to-unix", "ISO 8601 to Unix", "clock.arrow.2.circlepath", toolID: "date.unix", options: ["mode": "to-unix"]),
        .init("date.validate-iso", "Validate ISO 8601", "checkmark.circle", delivery: .compactResult, toolID: "date.iso8601"),

        .init("text.count-characters", "Count Characters", "character", delivery: .compactResult, toolID: "text.charCount"),
        .init("text.count-words", "Count Words", "textformat.size", delivery: .compactResult, toolID: "text.wordCount"),
        .init("text.count-lines", "Count Lines", "list.number", delivery: .compactResult, toolID: "text.lineCount"),
        .init("text.trim", "Trim Whitespace", "scissors", toolID: "text.trim"),
        .init("text.uppercase", "Uppercase", "textformat.abc", toolID: "text.case", options: ["mode": "upper"]),
        .init("text.lowercase", "Lowercase", "textformat.abc", toolID: "text.case", options: ["mode": "lower"]),
        .init("text.title-case", "Title Case", "textformat", toolID: "text.case", options: ["mode": "title"]),
        .init("text.camel-case", "camelCase", "textformat", toolID: "text.case", options: ["mode": "camel"]),
        .init("text.snake-case", "snake_case", "textformat", toolID: "text.case", options: ["mode": "snake"]),
        .init("text.slug", "Generate Slug", "link", toolID: "text.slug"),
        .init("text.dedupe-lines", "Remove Duplicate Lines", "list.bullet", toolID: "text.dedupe"),
        .init("text.sort-lines", "Sort Lines", "arrow.up.arrow.down", toolID: "text.sort", options: ["order": "asc"]),
        .init("text.sort-lines-descending", "Sort Lines Descending", "arrow.down", toolID: "text.sort", options: ["order": "desc"]),
        .init("text.reverse-lines", "Reverse Lines", "arrow.uturn.down", toolID: "text.reverse"),

        .init("code.format-sql", "Format SQL", "cylinder", toolID: "code.sqlFormat"),
        .init("code.format-html", "Format HTML", "chevron.left.slash.chevron.right", toolID: "code.html"),
        .init("code.format-css", "Format CSS", "paintpalette", toolID: "code.css"),
        .init("code.format-yaml", "Format YAML", "doc.plaintext", toolID: "code.yaml"),
        .init("code.format-xml", "Format XML", "doc.badge.gearshape", toolID: "code.xml"),
    ]

    static func action(id: String) -> QuickGlassActionDefinition? {
        all.first { $0.id == id }
    }
}
