import SwiftData
import SwiftUI
import SecondBrainCore

/// Associate follow-ups: what people asked for and what you promised, plus a people list
/// with interaction history.
struct AssociatesView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case followUps, people
        var id: String { rawValue }
        var title: String { self == .followUps ? "Follow-ups" : "People" }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var mode: Mode = .followUps
    @State private var search = ""
    @State private var showNewFollowUp = false
    @State private var showNewPerson = false
    @State private var showTeamSetup = false
    @State private var showArchived = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                if mode == .followUps { followUpSections } else { peopleSection }
                Section { PrivacyReminder() }
                Color.clear.frame(height: 72).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Associates")
            .searchable(text: $search, prompt: mode == .followUps ? "Search follow-ups" : "Search people")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { TeamListsView() } label: { Image(systemName: "list.bullet.clipboard") }
                        .accessibilityLabel("Team lead lists")
                        .accessibilityIdentifier("teamListsButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNewFollowUp = true } label: { Label("New Follow-up", systemImage: "person.crop.circle.badge.clock") }
                        Button { showNewPerson = true } label: { Label("Add Person", systemImage: "person.badge.plus") }
                        Button { showTeamSetup = true } label: { Label("Add Several People…", systemImage: "person.3") }
                        Toggle("Show Archived People", isOn: $showArchived)
                    } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $showNewFollowUp) { FollowUpEditorView(associate: nil) }
            .sheet(isPresented: $showNewPerson) { AssociateEditorView(associate: nil) }
            .sheet(isPresented: $showTeamSetup) { TeamSetupSheet() }
        }
    }

    // MARK: Follow-ups

    private var followUps: [TaskItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { t in
            guard t.kind == .followUp, t.status != .archived else { return false }
            guard !q.isEmpty else { return true }
            return [t.title, t.request, t.commitment, t.associate?.name ?? "", t.department].joined(separator: " ").lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var followUpSections: some View {
        let now = Date()
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let open = followUps.filter { $0.isOpen }
        let waiting = open.filter { $0.status == .waiting || $0.isAwaitingConfirmation }
        let active = open.filter { !($0.status == .waiting || $0.isAwaitingConfirmation) }
        let overdue = active.filter { $0.isOverdue(now: now) }
        let today = active.filter { !$0.isOverdue(now: now) && ($0.dueDate.map { $0 < endOfToday } ?? false) }
        let upcoming = active.filter { ($0.dueDate.map { $0 >= endOfToday } ?? false) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        let undated = active.filter { $0.dueDate == nil }
        let resolved = followUps.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }

        if open.isEmpty && resolved.isEmpty {
            ContentUnavailableView {
                Label("No follow-ups yet", systemImage: "person.crop.circle.badge.clock")
            } description: {
                Text("Capture “Sarah needs help with her schedule — talk to her tomorrow” and it lands here.")
            } actions: {
                Button("New Follow-up") { showNewFollowUp = true }.buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        }
        followUpSection("Overdue", overdue, tint: Theme.danger)
        followUpSection("Today", today, tint: Theme.accent)
        followUpSection("Upcoming", upcoming, tint: .secondary)
        followUpSection("No date", undated, tint: .secondary)
        followUpSection("Waiting on someone", waiting, tint: Theme.warning)
        if !resolved.isEmpty {
            Section("Resolved") {
                ForEach(resolved.prefix(25)) { t in
                    NavigationLink { TaskDetailView(task: t) } label: { FollowUpRow(task: t) }
                        .taskInteractions(t)
                }
            }
        }
    }

    @ViewBuilder
    private func followUpSection(_ title: String, _ items: [TaskItem], tint: Color) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items) { t in
                    NavigationLink { TaskDetailView(task: t) } label: { FollowUpRow(task: t) }
                        .taskInteractions(t)
                }
            } header: {
                Text("\(title) · \(items.count)").foregroundStyle(tint)
            }
        }
    }

    // MARK: People

    @ViewBuilder
    private var peopleSection: some View {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let people = associates.filter { a in
            (showArchived || !a.isArchived) && (q.isEmpty || a.name.lowercased().contains(q) || a.department.lowercased().contains(q))
        }
        if people.isEmpty {
            ContentUnavailableView {
                Label("No associates", systemImage: "person.2")
            } description: {
                Text("Add your team leads and associates, or they're added automatically when you capture a follow-up.")
            } actions: {
                Button("Add Several People") { showTeamSetup = true }.buttonStyle(.borderedProminent)
            }
            .listRowBackground(Color.clear)
        } else {
            // Grouped by role: Store Manager, Coaches, Team Leads, Associates.
            ForEach(StoreRole.allCases) { role in
                let group = people.filter { $0.storeRole == role }
                    .sorted { ($0.department, $0.name) < ($1.department, $1.name) }
                if !group.isEmpty {
                    Section("\(role.pluralTitle) · \(group.count)") {
                        ForEach(group) { person in
                            NavigationLink { AssociateDetailView(associate: person) } label: { PersonRow(person: person) }
                        }
                    }
                }
            }
            let unassigned = people.filter { $0.storeRole == nil }
            if !unassigned.isEmpty {
                Section("No role set · \(unassigned.count)") {
                    ForEach(unassigned) { person in
                        NavigationLink { AssociateDetailView(associate: person) } label: { PersonRow(person: person) }
                    }
                }
            }
            if !people.contains(where: { $0.storeRole == .teamLead }) {
                Section {
                    Button { showTeamSetup = true } label: {
                        Label("Add your team leads so you can delegate to them in one tap", systemImage: "person.3")
                    }
                }
            }
        }
    }
}

struct FollowUpRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompletionButton(task: task)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.associate?.name ?? "No associate")
                    .font(.subheadline.weight(.semibold))
                Text(task.request.isEmpty ? task.displayTitle : task.request)
                    .font(.subheadline)
                    .lineLimit(2)
                if !task.commitment.isEmpty {
                    Label(task.commitment, systemImage: "hand.thumbsup")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let due = task.dueDate, task.isOpen {
                        Text(RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: Date(), calendar: .current))
                            .foregroundStyle(task.isOverdue() ? Theme.danger : .secondary)
                    }
                    if task.isCompleted, let done = task.completedAt {
                        Text("Resolved \(RelativeDateText.dayLabel(for: done, now: Date(), calendar: .current))").foregroundStyle(.secondary)
                    }
                    if task.isAwaitingConfirmation {
                        Text("Waiting").foregroundStyle(Theme.warning)
                    }
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PersonRow: View {
    let person: Associate

    var body: some View {
        HStack(spacing: 12) {
            Text(person.initials)
                .font(.subheadline.weight(.bold))
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name).font(.body.weight(.medium))
                Text([person.role, person.department].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            let open = person.openFollowUps.count
            if open > 0 {
                Text("\(open)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background((person.hasOverdueFollowUp ? Theme.danger : Theme.accent).opacity(0.2), in: Capsule())
                    .foregroundStyle(person.hasOverdueFollowUp ? Theme.danger : Theme.accent)
                    .accessibilityLabel("\(open) open follow-ups")
            }
        }
    }
}
