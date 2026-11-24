import SwiftData
import SwiftUI
import SecondBrainCore

/// Home: what needs attention right now, in the order a shift actually runs.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.showSeasonOnHome, store: AppGroup.defaults) private var showSeasonOnHome = SettingsDefault.showSeasonOnHome
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var briefing: String = ""
    @State private var showCompleted = false
    @State private var now = Date()

    var body: some View {
        let agenda = DayAgenda.build(tasks: tasks.map(\.snapshot), day: now, now: now, calendar: .current)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(agenda)
                    quickActions
                    if !agenda.inbox.isEmpty { inboxBanner(count: agenda.inbox.count) }

                    focusCard(agenda, items: items)

                    TaskCard(title: "Overdue", systemImage: "exclamationmark.circle.fill", tint: Theme.danger,
                             tasks: items(agenda.overdue))
                    TaskCard(title: "Do first", systemImage: Quadrant.doFirst.systemImage, tint: Theme.color(for: .doFirst),
                             tasks: items(agenda.urgentImportant.filter { snap in !agenda.overdue.contains { $0.id == snap.id } }))
                    TaskCard(title: "Associate follow-ups", systemImage: "person.crop.circle.badge.clock", tint: Theme.accent,
                             tasks: items(agenda.followUpsDue.filter { snap in !agenda.overdue.contains { $0.id == snap.id } }),
                             showQuadrant: false)
                    TaskCard(title: "Due today", systemImage: "calendar", tint: Theme.accent,
                             tasks: items(agenda.dueToday.filter { $0.quadrant != .doFirst && $0.kind != .followUp }),
                             emptyText: agenda.dueToday.isEmpty && agenda.overdue.isEmpty ? "Nothing else is due today." : nil)
                    TaskCard(title: "Upcoming reminders", systemImage: "bell", tint: Theme.accent,
                             tasks: items(agenda.upcomingReminders), limit: 4)

                    if showSeasonOnHome { SeasonComingUpCard(now: now) }
                    upcoming(agenda, items: items)
                    completed(agenda, items: items)
                }
                .padding(.horizontal)
                .padding(.bottom, 96)
            }
            .background(Theme.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { router.open(.planner) } label: { Image(systemName: "calendar") }
                        .accessibilityLabel("Daily and weekly planner")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { router.open(.storeTerms(nil)) } label: { Image(systemName: "character.book.closed") }
                        .accessibilityLabel("Store terms")
                        .accessibilityIdentifier("storeTermsButton")
                    Button { router.open(.weeklyReview) } label: { Image(systemName: "chart.bar.doc.horizontal") }
                        .accessibilityLabel("Weekly review")
                    Button { router.open(.settings) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                        .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                now = Date()
                await AppMaintenance.runForegroundUpkeep()
            }
            .task(id: tasks.count) {
                now = Date()
                briefing = await BriefingAssistant.briefing(for: agenda, now: now)
            }
        }
    }

    // MARK: Sections

    private func header(_ agenda: DayAgenda) -> some View {
        let done = agenda.completedToday.count
        let total = done + agenda.dueToday.count + agenda.overdue.count
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(greeting)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.heroText)
                    .lineLimit(2)
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.heroSecondary)
                Capsule()
                    .fill(Theme.heroTrack)
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.heroProgress)
                            .scaleEffect(x: max(progress, 0.03), y: 1, anchor: .leading)
                    }
                    .accessibilityHidden(true)
                Text(total == 0 ? "Nothing due today" : "\(done) of \(total) done today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.heroSecondary)
                Button {
                    router.open(.shift)
                } label: {
                    Label("End My Shift", systemImage: "moon.stars")
                        .font(.headline)
                        .foregroundStyle(Theme.heroFill)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.heroText, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .accessibilityIdentifier("endShiftButton")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 8) {
                StatPill(value: agenda.overdue.count, label: "Overdue", tint: Theme.danger, systemImage: "exclamationmark.circle")
                StatPill(value: agenda.dueToday.count, label: "Today", tint: Theme.accent, systemImage: "calendar")
                StatPill(value: agenda.followUpsDue.count, label: "Follow-ups", tint: Theme.color(for: .schedule), systemImage: "person")
                StatPill(value: done, label: "Done", tint: Theme.success, systemImage: "checkmark")
            }
        }
    }

    /// First line of the briefing ("Good evening. You have 6 tasks due today…"), or a plain greeting.
    private var greeting: String {
        let first = briefing.split(separator: "\n").first.map(String.init) ?? ""
        if !first.isEmpty { return first }
        let hour = Calendar.current.component(.hour, from: now)
        return hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
    }

    /// "Tue, Nov 24 · Shift 7–5 · Wk 43"
    private var dateLine: String {
        let week = RetailCalendar.fiscalWeek(of: now, calendar: .current).week
        return now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + shiftLine + " · Wk \(week)"
    }

    /// "Shift 10–8" or "Off today · next shift Thu 12–10".
    private var shiftLine: String {
        let schedule = AppSettings.shiftSchedule
        let cal = Calendar.current
        if let shift = schedule.shift(on: Date(), calendar: cal) { return "Shift \(shift.shortLabel)" }
        let next = schedule.nextWorkday(after: Date(), calendar: cal)
        let label = schedule.shift(on: next, calendar: cal)?.shortLabel ?? ""
        return "Off today · next shift \(RelativeDateText.dayLabel(for: next, now: Date(), calendar: cal)) \(label)"
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                QuickActionButton(title: "Capture", systemImage: "bolt.fill", tint: Theme.accent) { router.open(.capture(nil)) }
                QuickActionButton(title: "Task", systemImage: "checklist", tint: Theme.color(for: .schedule)) { router.open(.capture(.task)) }
                QuickActionButton(title: "Follow-up", systemImage: "person.crop.circle.badge.clock", tint: Theme.purple) { router.open(.capture(.followUp)) }
                QuickActionButton(title: "Note", systemImage: "note.text", tint: Theme.warning) { router.open(.capture(.note)) }
                QuickActionButton(title: "Reminder", systemImage: "bell", tint: Theme.pink) { router.open(.capture(.reminder)) }
            }
        }
    }

    private func inboxBanner(count: Int) -> some View {
        Button {
            router.taskFilterRequest = .inbox
            router.open(.tab(.tasks))
        } label: {
            HStack {
                Image(systemName: "tray.full").foregroundStyle(Theme.warning)
                Text("\(count) item\(count == 1 ? "" : "s") in your Inbox to sort")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .card(tint: Theme.warning)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func focusCard(_ agenda: DayAgenda, items: ([TaskSnapshot]) -> [TaskItem]) -> some View {
        let chosen = items(agenda.topPriorities)
        let suggested = items(agenda.suggestedPriorities)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(title: chosen.isEmpty ? "Suggested priorities" : "Today's top 3", systemImage: "star.fill", tint: Theme.warning)
                Button(chosen.isEmpty ? "Choose" : "Change") { router.open(.planner) }
                    .font(.subheadline.weight(.semibold))
            }
            let list = chosen.isEmpty ? suggested : chosen
            if list.isEmpty {
                Text("You're clear. Capture something new or plan ahead.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { index, task in
                Button { router.open(.task(task.id)) } label: {
                    HStack(alignment: .top) {
                        Text("\(index + 1)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Theme.warning)
                            .frame(width: 22)
                        TaskRowView(task: task)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu { TaskQuickMenu(task: task) }
            }
        }
        .card()
    }

    @ViewBuilder
    private func upcoming(_ agenda: DayAgenda, items: ([TaskSnapshot]) -> [TaskItem]) -> some View {
        let tomorrow = items(agenda.tomorrow)
        let week = items(agenda.restOfWeek)
        let recurringSeries = Set(agenda.recurring.map(\.title))
        if !tomorrow.isEmpty || !week.isEmpty || !recurringSeries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Upcoming", systemImage: "calendar.badge.clock")
                if !tomorrow.isEmpty {
                    Text("Tomorrow").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(tomorrow.prefix(4)) { task in
                        Button { router.open(.task(task.id)) } label: { TaskRowView(task: task) }.buttonStyle(.plain)
                    }
                }
                if !week.isEmpty {
                    Text("Rest of the week").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(week.prefix(4)) { task in
                        Button { router.open(.task(task.id)) } label: { TaskRowView(task: task) }.buttonStyle(.plain)
                    }
                    if week.count > 4 {
                        Button("See the week") { router.open(.planner) }.font(.footnote)
                    }
                }
                if !recurringSeries.isEmpty {
                    Text("Recurring responsibilities").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text(recurringSeries.sorted().joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private func completed(_ agenda: DayAgenda, items: ([TaskSnapshot]) -> [TaskItem]) -> some View {
        let done = items(agenda.completedToday)
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { showCompleted.toggle() }
                } label: {
                    HStack {
                        SectionTitle(title: "Completed today", systemImage: "checkmark.circle.fill", count: done.count, tint: Theme.success)
                        Image(systemName: showCompleted ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if showCompleted {
                    ForEach(done) { task in TaskRowView(task: task, showQuadrant: false) }
                }
            }
            .card()
        }
    }
}

struct StatPill: View {
    let value: Int
    let label: String
    let tint: Color
    var systemImage: String? = nil

    var body: some View {
        let color = value > 0 ? tint : Color.secondary
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption.weight(.bold)).accessibilityHidden(true)
                }
                Text("\(value)").font(.title3.weight(.bold).monospacedDigit())
            }
            .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Theme.tint(color, value > 0 ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(Theme.tint(tint, 0.18), in: Circle())
                Text(title).font(.caption.weight(.medium))
            }
            .frame(width: 84, height: 80)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New \(title)")
    }
}
