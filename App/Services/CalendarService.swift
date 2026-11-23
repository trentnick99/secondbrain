import EventKit
import Foundation
import Observation

/// Optional Apple Calendar integration. The app never requires calendar access; tasks stay separate
/// from Calendar unless the person explicitly adds one as an event.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private(set) var revision = 0

    var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    var hasFullAccess: Bool { status == .fullAccess }
    var canWrite: Bool { status == .fullAccess || status == .writeOnly }

    var statusText: String {
        switch status {
        case .fullAccess: return "Connected"
        case .writeOnly: return "Add-only access"
        case .denied: return "Access denied in iOS Settings"
        case .restricted: return "Restricted on this iPhone"
        case .notDetermined: return "Not connected"
        @unknown default: return "Unavailable"
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            revision += 1
            return granted
        } catch {
            return false
        }
    }

    /// Call when returning to the foreground — access may have been revoked in iOS Settings.
    func refresh() {
        if hasFullAccess { store.reset() }
        revision += 1
    }

    func events(from start: Date, to end: Date) -> [EKEvent] {
        guard hasFullAccess, AppSettings.calendarEnabled else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func events(on day: Date) -> [EKEvent] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return events(from: start, to: end)
    }

    /// Calendar events that overlap a timed task (default 30-minute block).
    func conflicts(for task: TaskItem, durationMinutes: Int = 30) -> [EKEvent] {
        guard task.hasDueTime, let due = task.dueDate else { return [] }
        let end = due.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return events(from: due.addingTimeInterval(-1), to: end).filter { !$0.isAllDay }
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        guard !identifier.isEmpty, hasFullAccess else { return nil }
        return store.event(withIdentifier: identifier)
    }

    enum CalendarError: LocalizedError {
        case noAccess, noDate, noCalendar
        var errorDescription: String? {
            switch self {
            case .noAccess: return "Calendar access is off. Turn it on in Settings › Calendar."
            case .noDate: return "Give the task a date first."
            case .noCalendar: return "No default calendar is set on this iPhone."
            }
        }
    }

    /// Creates a calendar event for a task — only when the person explicitly asks.
    @discardableResult
    func addEvent(for task: TaskItem, durationMinutes: Int = 30) throws -> String {
        if status == .notDetermined || !canWrite { throw CalendarError.noAccess }
        guard let due = task.dueDate else { throw CalendarError.noDate }
        guard let calendar = store.defaultCalendarForNewEvents else { throw CalendarError.noCalendar }
        let event = EKEvent(eventStore: store)
        event.title = task.displayTitle
        event.notes = task.details.isEmpty ? "From Second Brain" : task.details
        event.calendar = calendar
        if task.hasDueTime {
            event.startDate = due
            event.endDate = due.addingTimeInterval(TimeInterval(durationMinutes * 60))
            event.isAllDay = false
        } else {
            event.startDate = Calendar.current.startOfDay(for: due)
            event.endDate = event.startDate.addingTimeInterval(86_400)
            event.isAllDay = true
        }
        try store.save(event, span: .thisEvent, commit: true)
        revision += 1
        return event.eventIdentifier ?? ""
    }
}
