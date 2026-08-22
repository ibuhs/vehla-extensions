import EventKit
import Foundation

actor CaptureHubWorker {
    static let shared = CaptureHubWorker()

    private let eventStore = EKEventStore()

    func perform(_ action: CaptureHubActionID, selectedText: String) async throws -> String {
        switch action {
        case .reminder:
            return try await addReminder(from: selectedText)
        case .reminderLines:
            return try await addReminderLines(from: selectedText)
        case .event:
            return try await addEvent(from: selectedText)
        case .note:
            return try createNote(from: selectedText)
        case .appendNote:
            return try appendToCaptureNote(selectedText)
        }
    }

    private func addReminder(from text: String) async throws -> String {
        let draft = try CaptureHubEngine.reminderDraft(from: text)
        try await requireRemindersAccess()
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw CaptureHubError.noWritableReminderList
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = draft.title
        reminder.calendar = calendar
        if let dueDate = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        try eventStore.save(reminder, commit: true)
        return draft.dueDate == nil
            ? "Added reminder “\(draft.title)”."
            : "Added reminder “\(draft.title)” with a due date."
    }

    private func addReminderLines(from text: String) async throws -> String {
        let titles = try CaptureHubEngine.reminderLines(from: text)
        try await requireRemindersAccess()
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw CaptureHubError.noWritableReminderList
        }

        for title in titles {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.calendar = calendar
            try eventStore.save(reminder, commit: false)
        }
        try eventStore.commit()
        return "Added \(titles.count) reminder\(titles.count == 1 ? "" : "s")."
    }

    private func addEvent(from text: String) async throws -> String {
        let draft = try CaptureHubEngine.eventDraft(from: text)
        try await requireEventsAccess()
        guard let calendar = writableEventCalendar() else {
            throw CaptureHubError.noWritableCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.notes = draft.notes
        event.calendar = calendar
        try eventStore.save(event, span: .thisEvent, commit: true)
        return "Created calendar event “\(draft.title)”."
    }

    private func requireRemindersAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToReminders() else {
                throw CaptureHubError.remindersPermissionDenied
            }
        default:
            throw CaptureHubError.remindersPermissionDenied
        }
    }

    private func requireEventsAccess() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await eventStore.requestFullAccessToEvents() else {
                throw CaptureHubError.eventsPermissionDenied
            }
        default:
            throw CaptureHubError.eventsPermissionDenied
        }
    }

    private func writableEventCalendar() -> EKCalendar? {
        if let calendar = eventStore.defaultCalendarForNewEvents,
           calendar.allowsContentModifications {
            return calendar
        }
        return eventStore.calendars(for: .event).first(where: \.allowsContentModifications)
    }

    private func createNote(from text: String) throws -> String {
        let title = try CaptureHubEngine.noteTitle(from: text)
        let body = CaptureHubEngine.html(from: try CaptureHubEngine.noteBody(from: text))
        let source = """
        tell application "Notes"
            set targetAccount to default account
            set targetFolder to default folder of targetAccount
            make new note at targetFolder with properties {name:"\(CaptureHubEngine.appleScriptString(title))", body:"\(CaptureHubEngine.appleScriptString(body))"}
        end tell
        """
        try runNotesScript(source)
        return "Created Apple Note “\(title)”."
    }

    private func appendToCaptureNote(_ text: String) throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureHubError.emptySelection
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]
        let timestamp = formatter.string(from: Date())
        let addition = "<br><br><b>\(CaptureHubEngine.html(from: timestamp))</b><br>"
            + CaptureHubEngine.html(from: text)
        let source = """
        tell application "Notes"
            set targetAccount to default account
            set targetFolder to default folder of targetAccount
            set matchingNotes to every note of targetFolder whose name is "Vehla Captures"
            if (count of matchingNotes) is 0 then
                set captureNote to make new note at targetFolder with properties {name:"Vehla Captures", body:"\(CaptureHubEngine.appleScriptString(addition))"}
            else
                set captureNote to item 1 of matchingNotes
                set body of captureNote to (body of captureNote) & "\(CaptureHubEngine.appleScriptString(addition))"
            end if
        end tell
        """
        try runNotesScript(source)
        return "Appended selection to Apple Note “Vehla Captures”."
    }

    private func runNotesScript(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else {
            throw CaptureHubError.notesFailure("The AppleScript could not be prepared.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        if number == -1743 {
            throw CaptureHubError.automationDenied
        }
        let message = errorInfo[NSAppleScript.errorMessage] as? String
            ?? "Unknown Automation error."
        throw CaptureHubError.notesFailure(message)
    }
}
