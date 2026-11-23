import Foundation
@testable import SecondBrainCore

/// Deterministic clock and calendar for every test: Monday, November 23, 2026 at 10:00 AM Central.
enum Fixtures {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Chicago")!
        c.locale = Locale(identifier: "en_US")
        c.firstWeekday = 1
        return c
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    /// Monday 2026-11-23 10:00.
    static var now: Date { date(2026, 11, 23, 10, 0) }

    static func context(known: [String] = [], now: Date = Fixtures.now, weekStartsOn: Int = 1) -> CaptureContext {
        CaptureContext(now: now, calendar: calendar, knownAssociates: known,
                       defaultReminderMinutes: 7 * 60, shiftStartMinutes: 7 * 60, shiftEndMinutes: 16 * 60,
                       weekStartsOn: weekStartsOn)
    }

    static func parse(_ text: String, known: [String] = [], now: Date = Fixtures.now) -> ParsedCapture {
        NaturalLanguageParser().parse(text, context: context(known: known, now: now))
    }

    static func day(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func time(_ date: Date?) -> String? {
        guard let date else { return nil }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    static func task(_ title: String,
                     kind: TaskKind = .task,
                     status: TaskStatus = .notStarted,
                     priority: TaskPriority = .normal,
                     quadrant: Quadrant = .schedule,
                     category: TaskCategory = .general,
                     due: Date? = nil,
                     hasTime: Bool = false,
                     reminder: Date? = nil,
                     completedAt: Date? = nil,
                     createdAt: Date = Fixtures.date(2026, 11, 20, 9),
                     updatedAt: Date? = nil,
                     associate: String? = nil,
                     focus: Date? = nil,
                     reschedules: Int = 0,
                     recurring: Bool = false,
                     delegatedTo: String? = nil,
                     confirmed: Bool = false) -> TaskSnapshot {
        TaskSnapshot(title: title, kind: kind, status: status, priority: priority, quadrant: quadrant,
                     category: category, dueDate: due, hasDueTime: hasTime, reminderDate: reminder,
                     completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt ?? createdAt,
                     associateName: associate, department: nil, focusDate: focus, rescheduleCount: reschedules,
                     isRecurring: recurring, delegatedTo: delegatedTo, delegationConfirmed: confirmed)
    }
}
