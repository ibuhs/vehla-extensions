import Foundation
import VehlaNativeUISDK

enum LinkLensActionID: String, CaseIterable, Sendable {
    case clean = "url.clean"
    case unwrap = "url.unwrap"
    case inspect = "url.inspect"
    case extract = "url.extract"
    case safety = "url.safety"

    var title: String {
        switch self {
        case .clean: "Remove Tracking"
        case .unwrap: "Unwrap Redirect"
        case .inspect: "Inspect Link"
        case .extract: "Extract Links"
        case .safety: "Check Link Safety"
        }
    }

    var systemImage: String {
        switch self {
        case .clean: "wand.and.stars"
        case .unwrap: "arrow.uturn.forward"
        case .inspect: "info.circle"
        case .extract: "link.badge.plus"
        case .safety: "checkmark.shield"
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery {
        switch self {
        case .clean, .unwrap: .replaceSelection
        case .inspect, .extract, .safety: .compactResult
        }
    }

    var needsNetwork: Bool {
        switch self {
        case .unwrap, .safety: true
        case .clean, .inspect, .extract: false
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

enum LinkLensActionCatalog {
    static let all: [LinkLensActionID] = LinkLensActionID.allCases

    static func action(id: String) -> LinkLensActionID? {
        LinkLensActionID(rawValue: id)
    }
}
