import EventKit
import SwiftData
import SwiftUI
import SecondBrainCore

struct PlannerContainerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var title: String { self == .day ? "Day" : "Week" }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .day

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Planner", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])
                if mode == .day { DailyPlannerView() } else { WeeklyPlannerView() }
            }
            .background(Theme.background)
            .navigationTitle("Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Daily planner

struct DailyPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @AppStorage(SettingsKey.calendarEnabled, store: AppGroup.defaults) private var calendarEnabled = false
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var showFocusPicker = false

    var body: some View {
        let now = Date()
        let agenda = DayAgenda.build(tasks: tasks.map(\.snapshot), day: day, now: now, calendar: .current)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }
        let isToday = Calendar.current.isDateInToday(day)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dayStrip
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SectionTitle(title: "Three main priorities", systemImage: "star.fill", tint: Theme.warning)
                        Button(agenda.topPriorities.isEmpty ? "Choose" : "Change") { showFocusPicker = true }
                            .font(.subheadline.weight(.semibold))
                    }
                    let chosen = items(agenda.topPriorities)
                    if chosen.isEmpty {
                        Text("Pick up to three things that would make \(isToday ? "today" : "this day") a success.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        let suggested = items(agenda.suggestedPriorities)
                        if !suggested.isEmpty {
                            Text("Suggested: " + suggested.map(\.displayTitle).joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(chosen.enumerated()), id: \.element.id) { index, task in
                        HStack(alignment: .top) {
                            Text("\(index + 1)").font(.headline).foregroundStyle(Theme.warning).frame(width: 20)
                            Button { router.open(.task(task.id)) } label: { TaskRowView(task: task) }.buttonStyle(.plain)
                        }
                    }
                }
                .card()

                if isToday {
                    TaskCard(title: "Overdue", systemImage: "exclamationmark.circle.fill", tint: Theme.danger, tasks: items(agenda.overdue))
                }
                TaskCard(title: "Q1 · Do first", systemImage: Quadrant.doFirst.systemImage, tint: Theme.color(for: .doFirst),
                         tasks: items(agenda.dueToday.filter { $0.quadrant == .doFirst }))
                TaskCard(title: "Q2 · Scheduled work", systemImage: Quadrant.schedule.systemImage, tint: Theme.color(for: .schedule),
                         tasks: items(agenda.dueToday.filter { $0.quadrant == .schedule && $0.kind != .followUp }))
                TaskCard(title: "Associate follow-ups", systemImage: "person.crop.circle.badge.clock", tint: Theme.accent,
                         tasks: items(agenda.dueToday.filter { $0.kind == .followUp }), showQuadrant: false)
                TaskCard(title: "Other tasks", systemImage: "checklist", tint: .secondary,
                         tasks: items(agenda.dueToday.filter { ($0.quadrant == .delegate || $0.quadrant == .eliminate) && $0.kind != .followUp }))
                TaskCard(title: "Recurring", systemImage: "repeat", tint: .secondary,
                         tasks: items(agenda.dueToday.filter(\.isRecurring)), showQuadrant: false)
                if isToday {
                    TaskCard(title: "Upcoming reminders", systemImage: "bell", tint: Theme.accent, tasks: items(agenda.upcomingReminders), limit: 5)
                }
                if calendarEnabled { CalendarEventsCard(day: day) }
                TaskCard(title: "Completed", systemImage: "checkmark.circle.fill", tint: Theme.success,
                         tasks: items(agenda.completedToday), showQuadrant: false)
                if agenda.dueToday.isEmpty && agenda.completedToday.isEmpty {
                    Text("Nothing scheduled for this day.").font(.subheadline).foregroundStyle(.secondary).padding()
                }
            }
            .padding()
        }
        .sheet(isPresented: $showFocusPicker) { FocusPickerSheet(day: day) }
    }

    private var dayStrip: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = (-1...6).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { d in
                    let selected = cal.isDate(d, inSameDayAs: day)
                    Button { day = d } label: {
                        VStack(spacing: 2) {
                            Text(RelativeDateText.weekdayShort(d, calendar: cal)).font(.caption2)
                            Text("\(cal.component(.day, from: d))").font(.headline)
                        }
                        .frame(width: 48, height: 56)
                        .background(selected ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(selected ? Color.black : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RelativeDateText.mediumDate(d, calendar: cal))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
}

/// Chooses up to three main priorities for a day, with ranked suggestions.
struct FocusPickerSheet: View {
    let day: Date
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var selected: [UUID] = []

    var body: some View {
        let ranked = PriorityRanker.ranked(tasks.filter { $0.isOpen && $0.status != .inbox }.map(\.snapshot), for: day, now: Date(), calendar: .current)
        let suggestedIDs = Set(PriorityRanker.suggestions(from: tasks.filter(\.isOpen).map(\.snapshot), for: day, now: Date(), calendar: .current).map(\.id))
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        NavigationStack {
            List {
                Section {
                    Text("Choose up to three. Suggestions (★) weigh quadrant, deadlines, safety and commitments.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("\(selected.count) of 3 selected") {
                    ForEach(ranked.prefix(40)) { snap in
                        if let task = lookup[snap.id] {
                            Button { toggle(task.id) } label: {
                                HStack {
                                    Image(systemName: selected.contains(task.id) ? "\(selected.firstIndex(of: task.id).map { $0 + 1 } ?? 1).circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(task.id) ? Theme.warning : .secondary)
                                        .font(.title3)
                                    TaskRowView(task: task)
                                    if suggestedIDs.contains(task.id) { Image(systemName: "star.fill").foregroundStyle(Theme.warning).font(.caption) }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Top 3")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let chosen = selected.compactMap { lookup[$0] }
                        TaskActions.setFocus(chosen, on: day, in: context)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selected = TaskActions.focusedTasks(on: day, in: context).map(\.id)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) }
        else if selected.count < 3 { selected.append(id) }
    }
}

struct CalendarEventsCard: View {
    let day: Date
    @State private var calendar = CalendarService.shared

    var body: some View {
        let events = calendar.events(on: day)
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Calendar", systemImage: "calendar", count: events.isEmpty ? nil : events.count)
            if !calendar.hasFullAccess {
                Text("Calendar access is off. Turn it on in Settings › Calendar.").font(.subheadline).foregroundStyle(.secondary)
            } else if events.isEmpty {
                Text("No calendar events.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(events, id: \.calendarItemIdentifier) { event in
                HStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 4, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title ?? "Event").font(.subheadline.weight(.medium))
                        Text(event.isAllDay ? "All day" : "\(RelativeDateText.timeText(event.startDate, calendar: .current)) – \(RelativeDateText.timeText(event.endDate, calendar: .current))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
        .id(calendar.revision)
    }
}

// MARK: - Weekly planner

struct WeeklyPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @AppStorage(SettingsKey.weekStartsOn, store: AppGroup.defaults) private var weekStartsOn = SettingsDefault.weekStartsOn
    @AppStorage(SettingsKey.calendarEnabled, store: AppGroup.defaults) private var calendarEnabled = false
    @State private var weekOffset = 0
    @State private var targetedDay: Date?

    private var days: [Date] {
        let math = DateMath(calendar: .current)
        let start = math.startOfWeek(containing: Date(), firstWeekday: weekStartsOn)
        let shifted = math.addingDays(weekOffset * 7, to: start)
        return math.weekDays(containing: shifted, firstWeekday: weekStartsOn)
    }

    var body: some View {
        let cal = Calendar.current
        let open = tasks.filter(\.isOpen)
        ScrollView {
            // Lazy so off-screen days aren't built until scrolled to.
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous week")
                    Spacer()
                    Text(weekTitle).font(.headline)
                    Spacer()
                    Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next week")
                }
                .padding(.horizontal, 4)
                if weekOffset != 0 {
                    Button("Back to this week") { weekOffset = 0 }.font(.footnote)
                }

                ForEach(days, id: \.self) { day in
                    let dayTasks = open.filter { t in t.dueDate.map { cal.isDate($0, inSameDayAs: day) } ?? false }
                        .sorted { a, b in a.quadrant.sortIndex == b.quadrant.sortIndex ? (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture) : a.quadrant.sortIndex < b.quadrant.sortIndex }
                    let doneCount = tasks.filter { $0.isCompleted && ($0.completedAt.map { cal.isDate($0, inSameDayAs: day) } ?? false) }.count
                    DaySection(day: day, tasks: dayTasks, doneCount: doneCount, days: days,
                               eventCount: calendarEnabled ? CalendarService.shared.events(on: day).count : 0,
                               isTargeted: targetedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false)
                        .dropDestination(for: String.self) { items, _ in
                            move(items, to: day)
                        } isTargeted: { on in
                            if on { targetedDay = day } else if targetedDay.map({ cal.isDate($0, inSameDayAs: day) }) == true { targetedDay = nil }
                        }
                }

                let overdue = open.filter { $0.isOverdue() }
                TaskCard(title: "Unfinished from earlier", systemImage: "exclamationmark.circle", tint: Theme.danger, tasks: overdue, limit: 5)
                TaskCard(title: "Outstanding associate requests", systemImage: "person.crop.circle.badge.clock", tint: Theme.accent,
                         tasks: open.filter { $0.kind == .followUp && $0.dueDate == nil }, limit: 5, showQuadrant: false)
                TaskCard(title: "Operational issues", systemImage: "exclamationmark.triangle", tint: Theme.warning,
                         tasks: open.filter { $0.kind == .issue }, limit: 5)
                Text("Drag a task onto another day to move it, or long-press for options.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var weekTitle: String {
        guard let first = days.first, let last = days.last else { return "" }
        let cal = Calendar.current
        return "\(RelativeDateText.mediumDate(first, calendar: cal)) – \(RelativeDateText.mediumDate(last, calendar: cal))"
    }

    private func move(_ ids: [String], to day: Date) -> Bool {
        var moved = false
        for raw in ids {
            guard let id = UUID(uuidString: raw), let task = TaskActions.task(with: id, in: context) else { continue }
            TaskActions.reschedule(task, to: day, in: context)
            moved = true
        }
        targetedDay = nil
        return moved
    }
}

struct DaySection: View {
    let day: Date
    let tasks: [TaskItem]
    let doneCount: Int
    let days: [Date]
    let eventCount: Int
    let isTargeted: Bool
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    var body: some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(RelativeDateText.dayLabel(for: day, now: Date(), calendar: cal))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isToday ? Theme.accent : .primary)
                Text(RelativeDateText.mediumDate(day, calendar: cal)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                ForEach(Quadrant.allCases) { q in
                    let n = tasks.filter { $0.quadrant == q }.count
                    if n > 0 {
                        Text("\(n)").font(.caption2.weight(.bold)).foregroundStyle(Theme.color(for: q))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.color(for: q).opacity(0.15), in: Capsule())
                            .accessibilityLabel("\(n) in \(q.code)")
                    }
                }
                if doneCount > 0 { Label("\(doneCount)", systemImage: "checkmark").font(.caption2).foregroundStyle(Theme.success) }
                if eventCount > 0 { Label("\(eventCount)", systemImage: "calendar").font(.caption2).foregroundStyle(.secondary) }
            }
            if tasks.isEmpty {
                Text("Nothing scheduled").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                Button { router.open(.task(task.id)) } label: { TaskRowView(task: task) }
                    .buttonStyle(.plain)
                    .draggable(task.id.uuidString)
                    .contextMenu {
                        Section("Move to") {
                            ForEach(days.filter { !cal.isDate($0, inSameDayAs: day) }, id: \.self) { d in
                                Button(RelativeDateText.dayLabel(for: d, now: Date(), calendar: cal) + " · " + RelativeDateText.shortDay(d, calendar: cal)) {
                                    TaskActions.reschedule(task, to: d, in: context)
                                }
                            }
                        }
                        Button { TaskActions.complete(task, in: context) } label: { Label("Complete", systemImage: "checkmark.circle") }
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isTargeted ? Theme.accent.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isTargeted ? Theme.accent : Theme.stroke, lineWidth: isTargeted ? 2 : 1))
    }
}
