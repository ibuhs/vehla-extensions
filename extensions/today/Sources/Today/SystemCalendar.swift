import EventKit
import Foundation
import TodayCore

enum Access { case unknown, granted, denied }

/// Calendar and Reminders through EventKit. Access is granted to Vehla itself, which already
/// carries the usage descriptions and entitlements; this only asks when you tap Allow.
@MainActor
final class SystemCalendar {
    private let store = EKEventStore()

    var eventAccess: Access { Self.access(EKEventStore.authorizationStatus(for: .event)) }
    var reminderAccess: Access { Self.access(EKEventStore.authorizationStatus(for: .reminder)) }

    private static func access(_ status: EKAuthorizationStatus) -> Access {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .unknown
        default: return .denied
        }
    }

    func requestEvents() async -> Bool { (try? await store.requestFullAccessToEvents()) ?? false }
    func requestReminders() async -> Bool { (try? await store.requestFullAccessToReminders()) ?? false }

    func events(on day: Date, calendar: Calendar = .current) -> [CalendarItem] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                CalendarItem(
                    id: event.eventIdentifier ?? "\(event.title ?? "")@\(event.startDate.timeIntervalSince1970)",
                    title: (event.title ?? "").isEmpty ? "Untitled" : event.title,
                    start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                    location: event.location.flatMap { $0.isEmpty ? nil : $0 },
                    joinURL: JoinLink.find(in: [event.url?.absoluteString, event.location, event.notes]))
            }
            .sorted { $0.start < $1.start }
    }

    /// Incomplete reminders due by the end of `day` (including overdue ones).
    func reminders(dueBy day: Date, calendar: Calendar = .current) async -> [ReminderItem] {
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { return [] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).map {
                    ReminderItem(id: $0.calendarItemIdentifier, title: $0.title ?? "Reminder",
                                 due: $0.dueDateComponents.flatMap { calendar.date(from: $0) })
                }
                continuation.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }
}
