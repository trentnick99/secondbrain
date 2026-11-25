import SwiftData
import SwiftUI
import SecondBrainCore

enum TaskFilter: String, CaseIterable, Identifiable {
    case today, myArea, upcoming, inbox, overdue, waiting, someday, completed, archived

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .myArea: return "My area"
        case .upcoming: return "Upcoming"
        case .inbox: return "Inbox"
        case .overdue: return "Overdue"
        case .waiting: return "Waiting"
        case .someday: return "No Date"
        case .completed: return "Completed"
        case .archived: return "Archived"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .myArea: return "person.crop.square"
        case .upcoming: return "calendar"
        case .inbox: return "tray"
        case .overdue: return "exclamationmark.circle"
        case .waiting: return "hourglass"
        case .someday: return "tray.2"
        case .completed: return "checkmark.circle"
        case .archived: return "archivebox"
        }
    }
}

struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var filter: TaskFilter = .today
    @State private var search = ""
    @State private var showRecurring = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filterBar
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if filter == .inbox && !visible.isEmpty {
                    Section {
                        Text("Captured quickly, not yet sorted. Tap Sort to apply the suggested date, person and quadrant — you'll see it first.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.tasks) { task in
                            NavigationLink {
                                TaskDetailView(task: task)
                            } label: {
                                if filter == .inbox {
                                    InboxRow(task: task, knownAssociates: associates.map(\.name))
                                } else {
                                    TaskRowView(task: task)
                                }
                            }
                            .taskInteractions(task)
                        }
                    }
                }
                if visible.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: filter.systemImage, description: Text(emptyMessage))
                        .listRowBackground(Color.clear)
                }
                Color.clear.frame(height: 72).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Tasks")
            .searchable(text: $search, prompt: "Search tasks, people, notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showRecurring = true } label: { Label("Recurring Tasks", systemImage: "repeat") }
                        Button { router.open(.planner) } label: { Label("Planner", systemImage: "calendar") }
                        Button { router.open(.shift) } label: { Label("End My Shift", systemImage: "moon.stars") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .sheet(isPresented: $showRecurring) { RecurringListView() }
            .onAppear(perform: applyFilterRequest)
            .onChange(of: router.taskFilterRequest) { _, _ in applyFilterRequest() }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableFilters) { f in
                    Chip(title: label(for: f), systemImage: f.systemImage, isSelected: filter == f) { filter = f }
                }
            }
            .padding(.horizontal)
        }
        .trailingFade()
    }

    /// "My area" appears once a role with an area is chosen (store managers already see everything).
    private var availableFilters: [TaskFilter] {
        guard let role = AppSettings.userRole, !role.seesWholeStore, role.primaryArea != nil else {
            return TaskFilter.allCases.filter { $0 != .myArea }
        }
        return TaskFilter.allCases
    }

    private func label(for f: TaskFilter) -> String {
        let count = tasks.filter { matches($0, f, now: Date()) }.count
        switch f {
        case .completed, .archived, .someday, .upcoming: return f.title
        default: return count > 0 ? "\(f.title) \(count)" : f.title
        }
    }

    private func applyFilterRequest() {
        if let request = router.taskFilterRequest {
            filter = request
            router.taskFilterRequest = nil
        }
    }

    // MARK: Filtering

    private func matches(_ t: TaskItem, _ f: TaskFilter, now: Date) -> Bool {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        switch f {
        case .today:
            guard t.isOpen, t.status != .inbox else { return false }
            if let due = t.dueDate { return due < endOfToday }
            if let focus = t.focusDate { return cal.isDate(focus, inSameDayAs: now) }
            return false
        case .myArea:
            guard t.isOpen, t.status != .inbox, let role = AppSettings.userRole else { return false }
            return MyAreaCard.belongs(t, to: role)
        case .upcoming:
            guard t.isOpen, let due = t.dueDate else { return false }
            return due >= endOfToday
        case .inbox: return t.status == .inbox
        case .overdue: return t.isOverdue(now: now)
        case .waiting: return t.isOpen && (t.status == .waiting || t.isAwaitingConfirmation)
        case .someday: return t.isOpen && t.status != .inbox && t.dueDate == nil
        case .completed: return t.status == .completed
        case .archived: return t.status == .archived
        }
    }

    private var visible: [TaskItem] {
        let now = Date()
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { t in
            if !q.isEmpty {
                let hay = [t.title, t.details, t.associate?.name ?? "", t.department, t.request, t.commitment].joined(separator: " ").lowercased()
                return hay.contains(q)
            }
            return matches(t, filter, now: now)
        }
    }

    private struct TaskGroup { let title: String; let tasks: [TaskItem] }

    private var groups: [TaskGroup] {
        let items = visible
        let now = Date()
        let cal = Calendar.current
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            return [TaskGroup(title: "Results", tasks: items.sorted { $0.isOpen && !$1.isOpen })]
        }
        switch filter {
        case .today:
            let overdue = items.filter { $0.isOverdue(now: now) }
            let rest = items.filter { !$0.isOverdue(now: now) }
            return [TaskGroup(title: "Overdue", tasks: sortByQuadrant(overdue)),
                    TaskGroup(title: "Today", tasks: sortByQuadrant(rest))].filter { !$0.tasks.isEmpty }
        case .upcoming:
            let byDay = Dictionary(grouping: items) { cal.startOfDay(for: $0.dueDate ?? now) }
            return byDay.keys.sorted().map { day in
                TaskGroup(title: RelativeDateText.dayLabel(for: day, now: now, calendar: cal) + " · " + RelativeDateText.mediumDate(day, calendar: cal),
                      tasks: sortByQuadrant(byDay[day] ?? []))
            }
        case .completed:
            let sorted = items.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return [TaskGroup(title: "Recently completed", tasks: Array(sorted.prefix(150)))]
        default:
            return items.isEmpty ? [] : [TaskGroup(title: filter.title, tasks: sortByQuadrant(items))]
        }
    }

    private func sortByQuadrant(_ items: [TaskItem]) -> [TaskItem] {
        items.sorted { a, b in
            if a.quadrant.sortIndex != b.quadrant.sortIndex { return a.quadrant.sortIndex < b.quadrant.sortIndex }
            if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
    }

    private var emptyTitle: String {
        search.isEmpty ? (filter == .today ? "Nothing due today" : "Nothing here") : "No matches"
    }

    private var emptyMessage: String {
        switch filter {
        case .inbox: return "Quick captures you save to the Inbox appear here for sorting."
        case .waiting: return "Delegated tasks and things you're waiting on show here until confirmed."
        case .today: return "Tap + to capture something, or check Upcoming."
        case .myArea: return "Open tasks for your areas and the total store show here. Import market notes to add some."
        default: return "Try another filter."
        }
    }
}

/// Inbox row with a one-tap "Sort" that shows the suggested interpretation for confirmation.
struct InboxRow: View {
    let task: TaskItem
    let knownAssociates: [String]
    @Environment(\.modelContext) private var context
    @State private var suggestion: DraftBox?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.displayTitle).lineLimit(3)
                Text("Captured \(RelativeDateText.dayLabel(for: task.createdAt, now: Date(), calendar: .current))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Sort") {
                suggestion = DraftBox(draft: CaptureSaver.suggestion(for: task, knownAssociates: knownAssociates))
            }
            .buttonStyle(.bordered)
        }
        .sheet(item: $suggestion) { box in
            InboxSortSheet(task: task, draft: box.draft)
        }
    }
}

struct DraftBox: Identifiable {
    let id = UUID()
    var draft: CaptureDraft
}

struct InboxSortSheet: View {
    let task: TaskItem
    @State var draft: CaptureDraft
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var showAdjust = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    InterpretationCard(draft: draft, onAdjust: { showAdjust = true })
                    if draft.needsReview {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(draft.ambiguities) { Text("• " + $0.message).font(.subheadline) }
                        }
                        .card()
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Sort Inbox Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        CaptureSaver.apply(draft, to: task, in: context)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAdjust) { CaptureAdjustSheet(draft: $draft, associates: associates) }
        }
        .presentationDetents([.medium, .large])
    }
}
