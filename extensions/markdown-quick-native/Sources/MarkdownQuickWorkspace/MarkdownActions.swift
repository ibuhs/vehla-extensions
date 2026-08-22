import Foundation
import VehlaNativeUISDK

enum MarkdownQuickActionID: String, CaseIterable, Sendable {
    case normalize = "md.normalize"
    case strip = "md.strip"
    case formatTables = "md.format-tables"
    case unwrapLinks = "md.unwrap-links"
    case extractLinks = "md.extract-links"
    case extractHeadings = "md.extract-headings"

    var title: String {
        switch self {
        case .normalize: "Normalize Markdown"
        case .strip: "Strip Markdown"
        case .formatTables: "Format Tables"
        case .unwrapLinks: "Links to URLs"
        case .extractLinks: "Extract Links"
        case .extractHeadings: "Extract Headings"
        }
    }

    var systemImage: String {
        switch self {
        case .normalize: "text.alignleft"
        case .strip: "textformat"
        case .formatTables: "tablecells"
        case .unwrapLinks: "link"
        case .extractLinks: "link.badge.plus"
        case .extractHeadings: "list.bullet.indent"
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery {
        switch self {
        case .normalize, .strip, .formatTables, .unwrapLinks: .replaceSelection
        case .extractLinks, .extractHeadings: .compactResult
        }
    }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum MarkdownQuickActionCatalog {
    static let all: [MarkdownQuickActionID] = MarkdownQuickActionID.allCases

    static func action(id: String) -> MarkdownQuickActionID? {
        MarkdownQuickActionID(rawValue: id)
    }
}
