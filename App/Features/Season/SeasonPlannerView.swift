import SwiftUI
import SwiftData
import SecondBrainCore

/// The next twelve months of holidays, announced sales events, seasonal sets and safety changes,
/// each with prep steps you can add as tasks. Nothing is added until you tap.
struct SeasonPlannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.seasonAdded, store: AppGroup.defaults) private var addedRaw = ""
    @AppStorage(SettingsKey.seasonHidden, store: AppGroup.defaults) private var hiddenRaw = ""
    @State private var showHidden = false
    @State private var confirmAll: RetailMoment?
    @AppStorage(SettingsKey.seasonMyAreasOnly, store: AppGroup.defaults) private var myAreasOnly = SettingsDefault.seasonMyAreasOnly
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @State private var now = Date()

    private var calendar: Calendar { .current }

    var body: some View {
        let added = SeasonPlanStore.keys(addedRaw)
        let hidden = SeasonPlanStore.keys(hiddenRaw)
        let all = RetailCalendar.upcoming(from: now, days: 365, calendar: calendar)
        let role = RoleStorage.decode(roleJSON)
        let filtering = myAreasOnly && SeasonFilter.canFilter(role)
        let visible = all.filter { (showHidden || !hidden.contains($0.key)) && (!filtering || SeasonFilter.isRelevant($0, to: role)) }

        NavigationStack {
            List {
                Section {
                    Label(RetailCalendar.fiscalWeekLabel(for: now, calendar: calendar), systemImage: "calendar")
                        .font(.headline)
                        .accessibilityIdentifier("fiscalWeekLabel")
                    if SeasonFilter.canFilter(role), let role {
                        Toggle("Only \(role.areasSummary) and store-wide", isOn: $myAreasOnly)
                            .accessibilityIdentifier("seasonMyAreasToggle")
                    }
                } footer: {
                    Text("Tap **Add** on a step to make it a task. Due dates move to your last workday before the event. Swipe an item to hide it if it doesn't apply to your store.")
                }

                ForEach(months(visible), id: \.start) { month in
                    Section(month.title) {
                        ForEach(month.moments) { moment in
                            MomentRow(moment: moment, now: now, added: added, isHidden: hidden.contains(moment.key),
                                      onAdd: { step in add(step, moment) },
                                      onAddAll: { confirmAll = moment })
                                .swipeActions {
                                    let isHidden = hidden.contains(moment.key)
                                    Button(isHidden ? "Show" : "Hide") {
                                        SeasonPlanStore.setHidden(moment.key, !isHidden)
                                        hiddenRaw = SeasonPlanStore.joined(SeasonPlanStore.hiddenKeys)
                                    }
                                    .tint(isHidden ? Theme.accent : .gray)
                                }
                        }
                    }
                }

                Section {
                    Toggle("Show hidden items (\(all.filter { hidden.contains($0.key) }.count))", isOn: $showHidden)
                } footer: {
                    Text("Holiday dates follow the calendar. Sales-event dates appear once Walmart announces them. Seasonal set timing is typical only, so check your store's modular and feature calendar. Everything stays on this iPhone.")
                }
            }
            .navigationTitle("Season Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog(confirmAll.map { "Add \(remaining($0, added: added).count) prep tasks for \($0.title)?" } ?? "",
                                isPresented: Binding(get: { confirmAll != nil }, set: { if !$0 { confirmAll = nil } }),
                                titleVisibility: .visible) {
                if let moment = confirmAll {
                    Button("Add \(remaining(moment, added: added).count) tasks") {
                        for step in remaining(moment, added: added) { add(step, moment) }
                        confirmAll = nil
                    }
                }
                Button("Cancel", role: .cancel) { confirmAll = nil }
            } message: {
                if let moment = confirmAll {
                    Text(remaining(moment, added: added).map { "• " + $0.title }.joined(separator: "\n"))
                }
            }
            .onAppear { now = Date() }
        }
    }

    private func remaining(_ moment: RetailMoment, added: Set<String>) -> [PrepStep] {
        moment.prep.filter { !added.contains($0.key) }
    }

    private func add(_ step: PrepStep, _ moment: RetailMoment) {
        SeasonPlanActions.addTask(for: step, in: moment, context: context, now: Date())
        addedRaw = SeasonPlanStore.joined(SeasonPlanStore.addedKeys)
    }

    private struct Month {
        let start: Date
        let title: String
        let moments: [RetailMoment]
    }

    private func months(_ moments: [RetailMoment]) -> [Month] {
        let grouped = Dictionary(grouping: moments) { moment -> Date in
            let start = max(moment.start, calendar.startOfDay(for: now))
            return calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return grouped.keys.sorted().map { key in
            Month(start: key, title: formatter.string(from: key), moments: grouped[key] ?? [])
        }
    }
}

private struct MomentRow: View {
    let moment: RetailMoment
    let now: Date
    let added: Set<String>
    let isHidden: Bool
    let onAdd: (PrepStep) -> Void
    let onAddAll: () -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        let remaining = moment.prep.filter { !added.contains($0.key) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: moment.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.color(for: moment.kind))
                    .frame(width: 32, height: 32)
                    .background(Theme.tint(Theme.color(for: moment.kind), 0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title).font(.headline)
                    Text(dateText).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isHidden { Image(systemName: "eye.slash").foregroundStyle(.secondary) }
            }
            HStack(spacing: 6) {
                badge(moment.kind.title, tint: Theme.color(for: moment.kind))
                badge(moment.certainty.label, tint: moment.certainty == .typical ? Theme.warning : .secondary)
            }
            if !moment.note.isEmpty {
                Text(moment.note).font(.footnote).foregroundStyle(.secondary)
            }
            if !moment.areas.isEmpty {
                Text(moment.areas.joined(separator: " · ")).font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(moment.prep) { step in
                let due = step.suggestedDue(for: moment, now: now, schedule: AppSettings.shiftSchedule, calendar: calendar)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline)
                        Text("\(step.category.title) · due \(RelativeDateText.dayLabel(for: due, now: now, calendar: calendar))")
                            .font(.caption)
                            .foregroundStyle(step.category == .safety ? Theme.warning : .secondary)
                    }
                    Spacer(minLength: 8)
                    if added.contains(step.key) {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.success)
                            .accessibilityLabel("Added")
                            .accessibilityIdentifier("seasonAddedMark")
                    } else {
                        Button("Add") { onAdd(step) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Add \(step.title)")
                            .accessibilityIdentifier("seasonAddButton")
                    }
                }
                .padding(.leading, 42)
            }
            if remaining.count > 1 {
                Button("Add all \(remaining.count)") { onAddAll() }
                    .buttonStyle(.borderless)
                    .font(.footnote.weight(.semibold))
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 4)
    }

    private var dateText: String {
        var text = RelativeDateText.mediumDate(moment.start, calendar: calendar)
        if let end = moment.end { text += " – " + RelativeDateText.mediumDate(end, calendar: calendar) }
        return text
    }

    private func badge(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.tint(tint, 0.16), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Shows the person's areas plus store-wide items (no areas listed) in the Season Planner and on Home.
enum SeasonFilter {
    static func canFilter(_ role: UserRole?) -> Bool {
        guard let role else { return false }
        return !role.seesWholeStore && role.primaryArea != nil
    }

    static func isRelevant(_ moment: RetailMoment, to role: UserRole?) -> Bool {
        guard let role, canFilter(role) else { return true }
        return moment.areas.isEmpty || moment.areas.contains(where: role.covers)
    }
}

/// Home card: what's coming up in the next three weeks, with prep still to add.
struct SeasonComingUpCard: View {
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.seasonAdded, store: AppGroup.defaults) private var addedRaw = ""
    @AppStorage(SettingsKey.seasonHidden, store: AppGroup.defaults) private var hiddenRaw = ""
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let added = SeasonPlanStore.keys(addedRaw)
        let hidden = SeasonPlanStore.keys(hiddenRaw)
        // The next three weeks — or, in a quiet stretch, just the next thing coming.
        let role = AppSettings.userRole
        let mine: (RetailMoment) -> Bool = { m in
            !hidden.contains(m.key) && (!AppGroup.defaults.bool(forKey: SettingsKey.seasonMyAreasOnly, default: SettingsDefault.seasonMyAreasOnly)
                                        || SeasonFilter.isRelevant(m, to: role))
        }
        let soon = RetailCalendar.upcoming(from: now, days: 21, calendar: calendar).filter(mine)
        let moments = soon.isEmpty
            ? Array(RetailCalendar.upcoming(from: now, days: 120, calendar: calendar).filter(mine).prefix(1))
            : Array(soon.prefix(3))
        if !moments.isEmpty {
            Button { router.open(.seasonPlanner) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionTitle(title: "Coming up", systemImage: "leaf.arrow.triangle.circlepath", tint: Theme.purple)
                        Spacer()
                        Text(RetailCalendar.fiscalWeekLabel(for: now, calendar: calendar))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(moments) { moment in
                        let toAdd = moment.prep.filter { !added.contains($0.key) }.count
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: moment.kind.systemImage)
                                .foregroundStyle(moment.kind == .safety ? Theme.warning : Theme.purple)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(moment.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(detail(moment, toAdd: toAdd, calendar: calendar))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    Text("Open Season Planner").font(.footnote.weight(.semibold)).foregroundStyle(Theme.purple)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .card(tint: Theme.purple)
            .accessibilityIdentifier("seasonComingUpCard")
        }
    }

    private func detail(_ moment: RetailMoment, toAdd: Int, calendar: Calendar) -> String {
        let when = RelativeDateText.dayLabel(for: moment.start, now: now, calendar: calendar)
        switch toAdd {
        case 0: return moment.prep.isEmpty ? when : "\(when) · prep added"
        case 1: return "\(when) · 1 prep step to add"
        default: return "\(when) · \(toAdd) prep steps to add"
        }
    }
}
