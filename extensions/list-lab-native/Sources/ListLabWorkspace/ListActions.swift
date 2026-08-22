import Foundation
import VehlaNativeUISDK

enum ListLabActionID: String, CaseIterable, Sendable {
    case splitComma = "list.split-comma"
    case joinComma = "list.join-comma"
    case splitPipe = "list.split-pipe"
    case joinPipe = "list.join-pipe"
    case shuffle = "list.shuffle"
    case number = "list.number"
    case quote = "list.quote"
    case wrapParens = "list.wrap-parens"
    case unwrap = "list.unwrap"
    case prefixClipboard = "list.prefix-clipboard"

    var title: String {
        switch self {
        case .splitComma: "Comma to Lines"
        case .joinComma: "Lines to Comma"
        case .splitPipe: "Pipe to Lines"
        case .joinPipe: "Lines to Pipe"
        case .shuffle: "Shuffle Lines"
        case .number: "Number Lines"
        case .quote: "Quote Lines"
        case .wrapParens: "Wrap ()"
        case .unwrap: "Unwrap"
        case .prefixClipboard: "Prefix with Clipboard"
        }
    }

    var systemImage: String {
        switch self {
        case .splitComma: "list.bullet"
        case .joinComma: "text.justify"
        case .splitPipe: "rectangle.split.1x2"
        case .joinPipe: "rectangle.split.2x1"
        case .shuffle: "shuffle"
        case .number: "list.number"
        case .quote: "quote.opening"
        case .wrapParens: "lanyardcard"
        case .unwrap: "pip.remove"
        case .prefixClipboard: "text.insert"
        }
    }

    var caption: String {
        switch self {
        case .splitComma: "Turns a, b, c into lines."
        case .joinComma: "Joins lines with commas."
        case .splitPipe: "Turns a | b | c into lines."
        case .joinPipe: "Joins lines with pipes."
        case .shuffle: "Randomizes the order of the lines."
        case .number: "Numbers each item from 1."
        case .quote: "Wraps each item in quotes."
        case .wrapParens: "Wraps each item in parentheses."
        case .unwrap: "Removes one layer of brackets or quotes."
        case .prefixClipboard: "Puts the clipboard text in front of each item."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery { .replaceSelection }

    var usesClipboard: Bool { self == .prefixClipboard }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum ListLabActionCatalog {
    static let all: [ListLabActionID] = ListLabActionID.allCases

    static func action(id: String) -> ListLabActionID? {
        ListLabActionID(rawValue: id)
    }
}
