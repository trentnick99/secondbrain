import SwiftData
import SwiftUI
import SecondBrainCore

/// Home: only what needs you right now. A header with today's counts and End My Shift, one status
/// line, four tools, today's top three, the next few things due, and pinned notes. Everything else
/// lives in Tasks, Notes, the planner and More tools.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    /// Open tasks plus what was finished since yesterday; a year of completed work is never loaded.
    @Query(TaskQueries.home()) private var tasks: [TaskItem]
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var showMoreTools = false
    @State private var pendingTool: Route?
    /// The clock Home is built from. Refreshed every minute, when the app comes back, and at midnight.
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    private let weather = WeatherAlertService.shared
    @AppStorage(SettingsKey.offDuty, store: AppGroup.defaults) private var offDuty = false
    @AppStorage(SettingsKey.shiftPlanBlocks, store: AppGroup.defaults) private var planJSON = ""

    var body: some View {
        let agenda = DayAgenda.build(tasks: tasks.map(\.snapshot), day: now, now: now, calendar: .current)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(agenda)
                    WeatherAlertBanner(alerts: weather.current)
                    statusLine
                    toolsGrid
                    focusCard(agenda, items: items)
                    nextUpCard(agenda, items: items)
                    if !pinnedNotes.isEmpty { notesCard }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.open(.settings) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
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
        VStack(alignment: .leading, spacing: 10) {
            Text(greeting)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.heroText)
                .accessibilityAddTraits(.isHeader)
            Text(dateLine)
                .font(.subheadline)
                .foregroundStyle(Theme.heroSecondary)
            Text(summary(agenda))
                .font(.subheadline)
                .foregroundStyle(Theme.heroText)
                .accessibilityIdentifier("homeSummary")
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

    /// "4 due · 3 overdue · 1 follow-up · 1 of 8 done", with the overdue count in bold.
    private func summary(_ agenda: DayAgenda) -> AttributedString {
        let done = agenda.completedToday.count
        let total = done + agenda.dueToday.count + agenda.overdue.count
        if total == 0 && agenda.followUpsDue.isEmpty { return AttributedString("Nothing due today") }
        var text = AttributedString("\(agenda.dueToday.count) due")
        if !agenda.overdue.isEmpty {
            text += AttributedString(" · ")
            var overdue = AttributedString("\(agenda.overdue.count) overdue")
            overdue.inlinePresentationIntent = .stronglyEmphasized
            text += overdue
        }
        let followUps = agenda.followUpsDue.count
        if followUps > 0 { text += AttributedString(" · \(followUps) follow-up\(followUps == 1 ? "" : "s")") }
        if total > 0 { text += AttributedString(" · \(done) of \(total) done") }
        return text
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
        var day = RelativeDateText.dayLabel(for: next, now: now, calendar: cal)
        if day == "Tomorrow" { day = "tomorrow" }
        return "Off today · next shift " + Self.keepTogether("\(day) \(label)")
    }

    /// Stops a line break inside "tomorrow 7–5": non-breaking space, and a word joiner around the dash.
    private static func keepTogether(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }

    /// Four tools in a compact 2×2 grid (one column at accessibility text sizes). Everything else is
    /// one tap away in More tools.
    @ViewBuilder
    private var toolsGrid: some View {
        let capture = ToolTile(id: "capture", title: "Capture", subtitle: "Task, note or follow-up",
                               systemImage: "bolt.fill", tint: Theme.accent) { router.open(.capture(nil)) }
        let walk = ToolTile(id: "floorwalk", title: "Floor walk", subtitle: "Check your areas",
                            systemImage: "figure.walk", tint: Theme.success) { router.open(.floorWalk) }
        let huddle = ToolTile(id: "huddle", title: "Huddle", subtitle: "Built from today",
                              systemImage: "megaphone.fill", tint: Theme.warning) { router.open(.huddle) }
        let more = ToolTile(id: "more", title: "More tools", subtitle: "Standards, timeline, import",
                            systemImage: "square.grid.2x2.fill", tint: Theme.purple) { showMoreTools = true }
        if typeSize.isAccessibilitySize {
            VStack(spacing: 10) { capture; walk; huddle; more }
        } else {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow { capture; walk }
                GridRow { huddle; more }
            }
        }
    }

    /// At most one line under the header: Off duty when the Focus is on, otherwise what's planned now.
    @ViewBuilder
    private var statusLine: some View {
        if offDuty {
            Label("Off duty. Your Focus is on, so work can wait.", systemImage: "moon.stars.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            nowBlock
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

    /// Only notes you pinned: the things you chose to keep in front of you.
    private var pinnedNotes: [Note] { Array(notes.filter(\.isPinned).prefix(3)) }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "Pinned notes", systemImage: "pin.fill", tint: Theme.warning)
                Button("See all") { router.open(.tab(.notes)) }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("homeNotesSeeAll")
            }
            ForEach(pinnedNotes) { note in
                NavigationLink { NoteEditorView(note: note) } label: { HomeNoteRow(note: note) }
                    .buttonStyle(.plain)
                if note.id != pinnedNotes.last?.id { Divider() }
            }
        }
        .card()
    }

    /// Overdue, then Do first, follow-ups and the rest due today, without what's already in the top 3.
    private func nextUp(_ agenda: DayAgenda) -> [TaskSnapshot] {
        let top = agenda.topPriorities.isEmpty ? agenda.suggestedPriorities : agenda.topPriorities
        var seen = Set(top.map(\.id))
        return (agenda.overdue + agenda.urgentImportant + agenda.followUpsDue + agenda.dueToday)
            .filter { seen.insert($0.id).inserted }
    }

    /// One short list instead of separate Overdue, Do first, Follow-ups and Due today cards.
    private func nextUpCard(_ agenda: DayAgenda, items: ([TaskSnapshot]) -> [TaskItem]) -> some View {
        let list = items(nextUp(agenda))
        let shown = Array(list.prefix(5))
        return VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Next up", systemImage: "list.bullet", tint: Theme.accent)
            if shown.isEmpty {
                Text("Nothing else is due today.").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 4)
            }
            ForEach(shown) { task in
                Button { router.open(.task(task.id)) } label: { TaskRowView(task: task) }
                    .buttonStyle(.plain)
                    .contextMenu { TaskQuickMenu(task: task) }
                if task.id != shown.last?.id { Divider().padding(.leading, 56) }
            }
            if list.count > shown.count || !agenda.inbox.isEmpty {
                HStack {
                    if list.count > shown.count {
                        Button("See all \(list.count) in Tasks") { openTasks(.today) }
                            .accessibilityIdentifier("nextUpSeeAll")
                    }
                    Spacer(minLength: 8)
                    if !agenda.inbox.isEmpty {
                        Button { openTasks(.inbox) } label: {
                            Label("\(agenda.inbox.count) to sort", systemImage: "tray.full")
                        }
                        .tint(Theme.warning)
                        .accessibilityIdentifier("homeInboxLink")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .card()
        .accessibilityIdentifier("nextUpCard")
    }

    private func openTasks(_ filter: TaskFilter) {
        router.taskFilterRequest = filter
        router.open(.tab(.tasks))
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

/// A compact tool button on Home: icon and name. The subtitle is read out by VoiceOver.
struct ToolTile: View {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = Theme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(Theme.tint(tint, 0.16), in: Circle())
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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
