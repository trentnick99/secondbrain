import SwiftData
import SwiftUI
import SecondBrainCore

/// Home: what needs attention right now, in the order a shift actually runs. Calm and roomy: a
/// header with the day's progress, four big tools, today's top three and your notes, then tasks.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.showSeasonOnHome, store: AppGroup.defaults) private var showSeasonOnHome = SettingsDefault.showSeasonOnHome
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var showMoreTools = false
    @State private var pendingTool: Route?
    @State private var showCompleted = false
    /// The clock Home is built from. Refreshed every minute, when the app comes back, and at midnight.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    private let weather = WeatherAlertService.shared
    @AppStorage(SettingsKey.offDuty, store: AppGroup.defaults) private var offDuty = false
    @AppStorage(SettingsKey.shiftPlanBlocks, store: AppGroup.defaults) private var planJSON = ""

    var body: some View {
        let agenda = DayAgenda.build(tasks: tasks.map(\.snapshot), day: now, now: now, calendar: .current)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(agenda)
                    if offDuty {
                        Label("Off duty. Your Focus is on, so work can wait.", systemImage: "moon.stars.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    WeatherAlertBanner(alerts: weather.current)
                    nowBlock
                    toolsGrid
                    if !agenda.inbox.isEmpty { inboxBanner(count: agenda.inbox.count) }

                    focusCard(agenda, items: items)
                    notesCard

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

                    if let role = RoleStorage.decode(roleJSON), role.seesWholeStore || role.primaryArea != nil {
                        if !role.seesWholeStore { MyAreaCard(role: role, tasks: tasks) }
                    } else {
                        RolePromptCard()
                    }
                    if showSeasonOnHome { SeasonComingUpCard(now: now) }
                    upcoming(agenda, items: items)
                    completed(agenda, items: items)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .background(Theme.background)
            .sheet(isPresented: $showMoreTools, onDismiss: {
                // Open the chosen tool once this sheet is gone, so two sheets never overlap.
                if let route = pendingTool { router.open(route) }
                pendingTool = nil
            }) {
                MoreToolsSheet { route in
                    pendingTool = route
                    showMoreTools = false
                }
            }
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { now = Date() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = Date() }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        }
    }

    // MARK: Sections

    private func header(_ agenda: DayAgenda) -> some View {
        let done = agenda.completedToday.count
        let total = done + agenda.dueToday.count + agenda.overdue.count
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        return VStack(alignment: .leading, spacing: 12) {
            Text(greeting)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.heroText)
                .accessibilityAddTraits(.isHeader)
            Text(dateLine)
                .font(.subheadline)
                .foregroundStyle(Theme.heroSecondary)
            HStack(spacing: 8) {
                HeroCount(value: agenda.dueToday.count, label: "due today")
                HeroCount(value: agenda.overdue.count, label: "overdue", alert: agenda.overdue.count > 0)
                if agenda.followUpsDue.count > 0 {
                    HeroCount(value: agenda.followUpsDue.count, label: agenda.followUpsDue.count == 1 ? "follow-up" : "follow-ups")
                }
            }
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
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Theme.heroText, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("endShiftButton")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.heroFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// First line of the briefing ("Good evening. You have 6 tasks due today…"), or a plain greeting.
    private var greeting: String { BriefingBuilder.greeting(now: now, calendar: .current) }

    /// "Tue, Nov 24 · Shift 7–5 · Wk 43"
    private var dateLine: String {
        let week = RetailCalendar.fiscalWeek(of: now, calendar: .current).week
        return now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " · " + shiftLine + " · Wk \(week)"
    }

    /// "Shift 10–8" or "Off today · next shift Thu 12–10".
    private var shiftLine: String {
        let schedule = AppSettings.shiftSchedule
        let cal = Calendar.current
        if let shift = schedule.shift(on: now, calendar: cal) { return "Shift \(shift.shortLabel)" }
        let next = schedule.nextWorkday(after: now, calendar: cal)
        let label = schedule.shift(on: next, calendar: cal)?.shortLabel ?? ""
        return "Off today · next shift \(RelativeDateText.dayLabel(for: next, now: now, calendar: cal)) \(label)"
    }

    /// Four big tools. Everything else is one tap away in More tools.
    private var toolsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                ToolTile(id: "capture", title: "Capture", subtitle: "Task, note or follow-up",
                         systemImage: "bolt.fill", tint: Theme.accent) { router.open(.capture(nil)) }
                ToolTile(id: "floorwalk", title: "Floor walk", subtitle: "Check your areas",
                         systemImage: "figure.walk", tint: Theme.success) { router.open(.floorWalk) }
            }
            GridRow {
                ToolTile(id: "huddle", title: "Huddle", subtitle: "Built from today",
                         systemImage: "megaphone.fill", tint: Theme.warning) { router.open(.huddle) }
                ToolTile(id: "more", title: "More tools", subtitle: "Standards, timeline, import",
                         systemImage: "square.grid.2x2.fill", tint: Theme.purple) { showMoreTools = true }
            }
        }
    }

    /// "Now: Work the freight · until 11:00 AM" from the shift plan, while on shift.
    @ViewBuilder
    private var nowBlock: some View {
        if let window = AppSettings.shiftWindow(on: now),
           let current = ShiftPlan.current(
               ShiftPlan.entries(blocks: ShiftPlanStorage.blocks(planJSON, role: RoleStorage.decode(roleJSON)),
                                 shiftStart: window.start, shiftEnd: window.end, tasks: []), now: now) {
            Button { router.open(.timeline) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.fill").foregroundStyle(Theme.accent)
                    Text("Now: ").foregroundStyle(.secondary) + Text(current.title).fontWeight(.semibold)
                    Spacer()
                    Text("until " + current.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("homeNowBlock")
        }
    }

    /// Pinned notes first, then the most recent: the things worth keeping in front of you.
    private var homeNotes: [Note] {
        Array((notes.filter(\.isPinned) + notes.filter { !$0.isPinned }).prefix(4))
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Notes", systemImage: "note.text", tint: Theme.purple)
                if !notes.isEmpty {
                    Button("See all") { router.open(.tab(.notes)) }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("homeNotesSeeAll")
                }
            }
            if homeNotes.isEmpty {
                Text("Jot down what you notice on the floor. Pinned notes stay here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(homeNotes) { note in
                NavigationLink { NoteEditorView(note: note) } label: { HomeNoteRow(note: note) }
                    .buttonStyle(.plain)
                if note.id != homeNotes.last?.id { Divider() }
            }
            Button { router.open(.capture(.note)) } label: {
                Label("New note", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.top, 2)
            .accessibilityIdentifier("homeNewNote")
        }
        .card()
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

/// "4 due today" on the header.
private struct HeroCount: View {
    let value: Int
    let label: String
    var alert = false

    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.subheadline)
        }
        .foregroundStyle(alert ? Theme.heroFill : Theme.heroText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(alert ? Theme.heroText : Theme.heroTrack, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A big, quiet tool button on Home.
struct ToolTile: View {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(Theme.tint(tint, 0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityIdentifier("tool-\(id)")
    }
}

/// One note on Home: title, a line of the body and when it changed.
private struct HomeNoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: note.isPinned ? "pin.fill" : note.type.systemImage)
                .font(.subheadline)
                .foregroundStyle(note.isPinned ? Theme.warning : Theme.purple)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !note.snippet.isEmpty {
                    Text(note.snippet).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(RelativeDateText.dayLabel(for: note.updatedAt, now: Date(), calendar: .current))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Every other tool, grouped. Picking one closes this sheet, then Home opens the tool.
struct MoreToolsSheet: View {
    let choose: (Route) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    row("Task", "checklist", Theme.color(for: .schedule), .capture(.task))
                    row("Follow-up", "person.crop.circle.badge.clock", Theme.purple, .capture(.followUp))
                    row("Note", "note.text", Theme.warning, .capture(.note))
                    row("Reminder", "bell", Theme.pink, .capture(.reminder))
                }
                Section("On the floor") {
                    row("Standards", "list.clipboard", Theme.accent, .standards(nil))
                    row("Shift timeline", "clock.fill", Theme.accent, .timeline)
                    row("Walk notes", "mic.fill", Theme.pink, .importNotes(nil, mode: .speak))
                    row("Import notes", "square.and.arrow.down", Theme.purple, .importNotes(nil))
                    NavigationLink { TeamListsView() } label: {
                        MoreToolLabel(title: "Team lead lists", systemImage: "list.bullet.clipboard", tint: Theme.success)
                    }
                    .accessibilityIdentifier("moreTool-Team lead lists")
                }
                Section("Plan and review") {
                    row("Planner", "calendar", Theme.color(for: .schedule), .planner)
                    row("Season planner", "leaf", Theme.success, .seasonPlanner)
                    row("Weekly review", "chart.bar.doc.horizontal", Theme.accent, .weeklyReview)
                    row("Store terms", "character.book.closed", Theme.warning, .storeTerms(nil))
                }
            }
            .navigationTitle("More tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func row(_ title: String, _ systemImage: String, _ tint: Color, _ route: Route) -> some View {
        Button { choose(route) } label: {
            MoreToolLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("moreTool-\(title)")
    }
}

private struct MoreToolLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Theme.tint(tint, 0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
        }
    }
}
