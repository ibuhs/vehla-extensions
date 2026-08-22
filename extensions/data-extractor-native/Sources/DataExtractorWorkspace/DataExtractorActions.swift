import Foundation
import VehlaNativeUISDK

enum DataExtractorActionID: String, CaseIterable, Sendable {
    case emails = "data.emails"
    case phones = "data.phones"
    case ips = "data.ips"
    case mentions = "data.mentions"
    case hashtags = "data.hashtags"
    case all = "data.all"
    case csv = "data.csv"

    var title: String {
        switch self {
        case .emails: "Extract Emails"
        case .phones: "Extract Phones"
        case .ips: "Extract IPs"
        case .mentions: "Extract Mentions"
        case .hashtags: "Extract Hashtags"
        case .all: "Extract All"
        case .csv: "Extract CSV"
        }
    }

    var systemImage: String {
        switch self {
        case .emails: "envelope"
        case .phones: "phone"
        case .ips: "network"
        case .mentions: "at"
        case .hashtags: "number"
        case .all: "text.badge.plus"
        case .csv: "tablecells"
        }
    }

    var caption: String {
        switch self {
        case .emails: "Lists unique email addresses."
        case .phones: "Lists unique phone numbers."
        case .ips: "Lists unique IPv4 and IPv6 addresses."
        case .mentions: "Lists unique @names."
        case .hashtags: "Lists unique #tags."
        case .all: "Groups every match by type."
        case .csv: "Exports matches as type,value CSV."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery { .compactResult }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum DataExtractorActionCatalog {
    static let all: [DataExtractorActionID] = DataExtractorActionID.allCases

    static func action(id: String) -> DataExtractorActionID? {
        DataExtractorActionID(rawValue: id)
    }
}
