import Foundation
import VehlaNativeUISDK

enum CaptureHubActionID: String, CaseIterable, Sendable {
    case reminder = "capture.reminder"
    case reminderLines = "capture.reminder-lines"
    case event = "capture.event"
    case note = "capture.note"
    case appendNote = "capture.append-note"

    var title: String {
        switch self {
        case .reminder: "Add Reminder"
        case .reminderLines: "Add Lines as Reminders"
        case .event: "Create Calendar Event"
        case .note: "Create Apple Note"
        case .appendNote: "Append to Capture Note"
        }
    }

    var systemImage: String {
        switch self {
        case .reminder: "checklist"
        case .reminderLines: "list.bullet"
        case .event: "calendar.badge.plus"
        case .note: "note.text.badge.plus"
        case .appendNote: "note.text"
        }
    }

    var caption: String {
        switch self {
        case .reminder: "Creates one reminder and recognizes a due date."
        case .reminderLines: "Creates one reminder for each non-empty line."
        case .event: "Creates an event from recognized dates and durations."
        case .note: "Creates a note using the first line as its name."
        case .appendNote: "Adds a timestamped capture to Vehla Captures."
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

enum CaptureHubActionCatalog {
    static let all = CaptureHubActionID.allCases

    static func action(id: String) -> CaptureHubActionID? {
        CaptureHubActionID(rawValue: id)
    }
}
