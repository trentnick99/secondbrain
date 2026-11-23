import Foundation
import SwiftData
import WidgetKit
import SecondBrainCore

/// Everything a widget shows, read from the shared App Group store.
struct WidgetEntry: TimelineEntry {
    struct Item: Identifiable, Hashable {
        let id: UUID
        let title: String
        let subtitle: String
        let quadrant: Quadrant
        let isOverdue: Bool
    }

    let date: Date
    let primary: Item?
    let top: [Item]
    let followUps: [Item]
    let nextReminderTitle: String?
    let nextReminderDate: Date?
    let openCount: Int
    let overdueCount: Int
    let priorityCount: Int
    let dueTodayCount: Int
    let quadrantCounts: [Quadrant: Int]
    let isAvailable: Bool

    static var placeholder: WidgetEntry {
        let id = UUID()
        let item = Item(id: id, title: "Review safety observations", subtitle: "Today 8:00 AM", quadrant: .doFirst, isOverdue: false)
        return WidgetEntry(date: Date(), primary: item,
                           top: [item,
                                 Item(id: UUID(), title: "Follow up on schedule question", subtitle: "Today", quadrant: .schedule, isOverdue: false),
                                 Item(id: UUID(), title: "Prep visit notes", subtitle: "Thu", quadrant: .schedule, isOverdue: false)],
                           followUps: [Item(id: UUID(), title: "Availability request", subtitle: "Associate · Tomorrow", quadrant: .schedule, isOverdue: false)],
                           nextReminderTitle: "Review safety observations", nextReminderDate: Date().addingTimeInterval(3600),
                           openCount: 8, overdueCount: 1, priorityCount: 3, dueTodayCount: 4,
                           quadrantCounts: [.doFirst: 2, .schedule: 4, .delegate: 1, .eliminate: 1], isAvailable: true)
    }
}

enum WidgetDataLoader {
    static func load(now: Date = Date()) -> WidgetEntry {
        let context = ModelContext(PersistenceController.shared)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let snapshots = tasks.map(\.snapshot)
        let cal = Calendar.current
        let agenda = DayAgenda.build(tasks: snapshots, day: now, now: now, calendar: cal)

        func item(_ s: TaskSnapshot) -> WidgetEntry.Item {
            var subtitle = ""
            if let due = s.dueDate {
                subtitle = RelativeDateText.dueText(due: due, hasTime: s.hasDueTime, now: now, calendar: cal)
            }
            if s.kind == .followUp, let name = s.associateName {
                subtitle = subtitle.isEmpty ? name : "\(name) · \(subtitle)"
            }
            return WidgetEntry.Item(id: s.id, title: s.title, subtitle: subtitle, quadrant: s.quadrant,
                                    isOverdue: s.isOverdue(now: now, calendar: cal))
        }

        var top = agenda.topPriorities
        if top.isEmpty { top = agenda.suggestedPriorities }
        // Fill up to five with overdue and due-today work for the large widget.
        for s in agenda.overdue + agenda.dueToday where top.count < 5 && !top.contains(where: { $0.id == s.id }) {
            top.append(s)
        }

        var counts: [Quadrant: Int] = [:]
        for q in Quadrant.allCases { counts[q] = snapshots.filter { $0.isOpen && $0.status != .inbox && $0.quadrant == q }.count }

        let followUps = snapshots.filter { $0.isOpen && $0.kind == .followUp }.sortedByDue()

        return WidgetEntry(
            date: now,
            primary: agenda.primaryTask.map(item),
            top: top.map(item),
            followUps: followUps.prefix(4).map(item),
            nextReminderTitle: agenda.nextReminder?.title,
            nextReminderDate: agenda.nextReminder?.reminderDate,
            openCount: agenda.openCount,
            overdueCount: agenda.overdue.count,
            priorityCount: agenda.priorityCount,
            dueTodayCount: agenda.dueToday.count,
            quadrantCounts: counts,
            isAvailable: AppGroup.isAvailable
        )
    }

    /// Refresh at the next reminder, the next midnight, or in 30 minutes — whichever comes first.
    /// iOS may delay refreshes to conserve battery; the app also reloads widgets after every change.
    static func nextRefresh(after entry: WidgetEntry) -> Date {
        let cal = Calendar.current
        var candidates: [Date] = [entry.date.addingTimeInterval(30 * 60)]
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: entry.date)) { candidates.append(midnight) }
        if let reminder = entry.nextReminderDate, reminder > entry.date { candidates.append(reminder.addingTimeInterval(60)) }
        return candidates.min() ?? entry.date.addingTimeInterval(1800)
    }
}

struct SecondBrainTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        if context.isPreview { completion(.placeholder); return }
        completion(WidgetDataLoader.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetDataLoader.load()
        completion(Timeline(entries: [entry], policy: .after(WidgetDataLoader.nextRefresh(after: entry))))
    }
}
