import Foundation
import VehlaNativeUISDK

enum TypePolishActionID: String, CaseIterable, Sendable {
    case straightenQuotes = "type.straighten-quotes"
    case cleanDashes = "type.clean-dashes"
    case unwrap = "type.unwrap"
    case collapseSpaces = "type.collapse-spaces"
    case stripJunk = "type.strip-junk"
    case polish = "type.polish"

    var title: String {
        switch self {
        case .straightenQuotes: "Straighten Quotes"
        case .cleanDashes: "Clean Dashes"
        case .unwrap: "Unwrap Lines"
        case .collapseSpaces: "Collapse Spaces"
        case .stripJunk: "Strip Invisible"
        case .polish: "Polish Text"
        }
    }

    var systemImage: String {
        switch self {
        case .straightenQuotes: "quote.closing"
        case .cleanDashes: "minus"
        case .unwrap: "text.justify.left"
        case .collapseSpaces: "arrow.left.and.right"
        case .stripJunk: "eraser"
        case .polish: "sparkles"
        }
    }

    var caption: String {
        switch self {
        case .straightenQuotes: "Turns curly quotes into straight quotes."
        case .cleanDashes: "Turns em/en dashes and ellipses into ASCII."
        case .unwrap: "Joins hard-wrapped lines into paragraphs."
        case .collapseSpaces: "Collapses extra spaces, tabs, and NBSP."
        case .stripJunk: "Removes zero-width marks and soft hyphens."
        case .polish: "Runs every cleanup in one pass."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery { .replaceSelection }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum TypePolishActionCatalog {
    static let all: [TypePolishActionID] = TypePolishActionID.allCases

    static func action(id: String) -> TypePolishActionID? {
        TypePolishActionID(rawValue: id)
    }
}
