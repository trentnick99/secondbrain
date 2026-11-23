import SwiftData
import SwiftUI
import SecondBrainCore

enum MatrixScope: String, CaseIterable, Identifiable {
    case all, today, week
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All open"
        case .today: return "Today"
        case .week: return "This week"
        }
    }
}

/// The Eisenhower Matrix: a full four-quadrant overview with drag-and-drop between quadrants,
/// and a swipeable full-screen view of each quadrant.
struct MatrixView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var scope: MatrixScope = .all
    @State private var expanded: QuadrantSelection?
    @State private var showEscalations = false
    @State private var pendingDrop: (task: TaskItem, quadrant: Quadrant)?
    @State private var showGuide = false

    struct QuadrantSelection: Identifiable { let quadrant: Quadrant; var id: String { quadrant.rawValue } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Scope", selection: $scope) {
                        ForEach(MatrixScope.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if !escalations.isEmpty { escalationBanner }

                    axisLabels
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(Quadrant.allCases) { q in
                            QuadrantCard(quadrant: q, tasks: items(in: q), onOpen: { expanded = QuadrantSelection(quadrant: q) },
                                         onDrop: { ids in handleDrop(ids, into: q) })
                        }
                    }

                    if !unsorted.isEmpty { unsortedTray }

                    Text("Drag a task onto another quadrant to move it, or long-press a task for options. Tap a quadrant to work through it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.bottom, 96)
            }
            .background(Theme.background)
            .navigationTitle("Matrix")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How the matrix works")
                }
            }
            .sheet(item: $expanded) { selection in
                QuadrantPagerView(start: selection.quadrant, scope: scope)
            }
            .sheet(isPresented: $showEscalations) { EscalationReviewSheet(tasks: escalations) }
            .sheet(isPresented: $showGuide) { MatrixGuideView() }
            .confirmationDialog("Safety & compliance work is always treated as important.",
                                isPresented: Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } }),
                                titleVisibility: .visible) {
                if let drop = pendingDrop {
                    Button("Move to \(drop.quadrant.code) anyway") {
                        TaskActions.setQuadrant(drop.task, drop.quadrant, in: context)
                        pendingDrop = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingDrop = nil }
            }
        }
    }

    // MARK: Data

    private var scoped: [TaskItem] {
        let cal = Calendar.current
        let now = Date()
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let endOfWeek = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now)) ?? now
        return tasks.filter { t in
            guard t.isOpen else { return false }
            switch scope {
            case .all: return true
            case .today:
                if let due = t.dueDate { return due < endOfToday }
                return t.focusDate.map { cal.isDateInToday($0) } ?? false
            case .week:
                if let due = t.dueDate { return due < endOfWeek }
                return false
            }
        }
    }

    private func items(in q: Quadrant) -> [TaskItem] {
        scoped.filter { $0.status != .inbox && $0.quadrant == q }
            .sorted { a, b in
                if a.priority.rank != b.priority.rank { return a.priority.rank < b.priority.rank }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    private var unsorted: [TaskItem] { scoped.filter { $0.status == .inbox } }

    /// Tasks whose deadline is now close enough to be urgent. Suggestions only — the person confirms.
    private var escalations: [TaskItem] {
        let now = Date()
        return tasks.filter { t in
            // A quadrant the person chose (or confirmed) sticks.
            guard t.isOpen, t.status != .inbox, !t.classificationIsManual else { return false }
            return EisenhowerClassifier.urgencyEscalation(current: t.quadrant, dueDate: t.dueDate, hasDueTime: t.hasDueTime,
                                                          isSafetyCritical: t.category.isSafetyCritical,
                                                          now: now, calendar: .current) != nil
        }
    }

    private func handleDrop(_ ids: [String], into q: Quadrant) -> Bool {
        var moved = false
        for raw in ids {
            guard let id = UUID(uuidString: raw), let task = TaskActions.task(with: id, in: context) else { continue }
            if task.category.isSafetyCritical && !q.isImportant {
                pendingDrop = (task, q)
            } else if task.quadrant != q || task.status == .inbox {
                TaskActions.setQuadrant(task, q, in: context)
            }
            moved = true
        }
        return moved
    }

    // MARK: Views

    private var axisLabels: some View {
        HStack {
            Text("URGENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            Text("NOT URGENT").font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        }
        .accessibilityHidden(true)
    }

    private var escalationBanner: some View {
        Button { showEscalations = true } label: {
            HStack(alignment: .top) {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Theme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(escalations.count) task\(escalations.count == 1 ? " is" : "s are") now due soon")
                        .font(.subheadline.weight(.semibold))
                    Text("Review whether to move them to an urgent quadrant.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var unsortedTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Unsorted (Inbox)", systemImage: "tray", count: unsorted.count, tint: Theme.warning)
            Text("Drag onto a quadrant to classify.").font(.caption).foregroundStyle(.secondary)
            ForEach(unsorted.prefix(8)) { task in
                Text(task.displayTitle)
                    .font(.subheadline)
                    .lineLimit(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10))
                    .draggable(task.id.uuidString)
                    .contextMenu {
                        ForEach(Quadrant.allCases) { q in
                            Button("\(q.code) · \(q.title)") { TaskActions.setQuadrant(task, q, in: context) }
                        }
                    }
            }
        }
        .card()
    }
}

/// One quadrant tile in the overview.
struct QuadrantCard: View {
    let quadrant: Quadrant
    let tasks: [TaskItem]
    let onOpen: () -> Void
    let onDrop: ([String]) -> Bool
    @State private var isTargeted = false
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpen) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(quadrant.code) · \(quadrant.title.uppercased())")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(Theme.color(for: quadrant))
                        Text(quadrant.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 2)
                    Text("\(tasks.count)").font(.title2.weight(.bold).monospacedDigit())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(quadrant.code) \(quadrant.title), \(tasks.count) tasks")
            .accessibilityHint("Opens the quadrant")

            if tasks.isEmpty {
                Text(emptyText).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            } else {
                ForEach(tasks.prefix(4)) { task in
                    MatrixTaskChip(task: task)
                }
                if tasks.count > 4 {
                    Button("+\(tasks.count - 4) more", action: onOpen).font(.caption.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(Theme.color(for: quadrant).opacity(isTargeted ? 0.25 : 0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Theme.color(for: quadrant).opacity(isTargeted ? 0.9 : 0.25), lineWidth: isTargeted ? 2 : 1))
        .dropDestination(for: String.self) { items, _ in
            onDrop(items)
        } isTargeted: { isTargeted = $0 }
    }

    private var emptyText: String {
        switch quadrant {
        case .doFirst: return "No fires right now."
        case .schedule: return "Plan development, reviews and prep here."
        case .delegate: return "Nothing to hand off."
        case .eliminate: return "Nothing to question."
        }
    }
}

struct MatrixTaskChip: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var pending: Quadrant?

    var body: some View {
        Button { router.open(.task(task.id)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayTitle).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    if let due = task.dueDate {
                        Text(RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: Date(), calendar: .current))
                            .foregroundStyle(task.isOverdue() ? Theme.danger : .secondary)
                    }
                    if let name = task.associate?.name { Text("· \(name)").foregroundStyle(.secondary) }
                }
                .font(.caption2)
                .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .draggable(task.id.uuidString) {
            Text(task.displayTitle).font(.caption).padding(8).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        }
        .contextMenu {
            Button { TaskActions.complete(task, in: context) } label: { Label("Complete", systemImage: "checkmark.circle") }
            ForEach(Quadrant.allCases.filter { $0 != task.quadrant }) { q in
                Button {
                    if task.category.isSafetyCritical && !q.isImportant { pending = q } else { TaskActions.setQuadrant(task, q, in: context) }
                } label: { Label("Move to \(q.code) \(q.title)", systemImage: q.systemImage) }
            }
            Button { router.open(.task(task.id)) } label: { Label("Edit", systemImage: "pencil") }
        }
        .safetyMoveConfirmation(task: task, pending: $pending)
    }
}

/// Swipe between quadrants; each page is a full list with swipe actions.
struct QuadrantPagerView: View {
    let start: Quadrant
    let scope: MatrixScope
    @State private var current: Quadrant = .doFirst
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(Quadrant.allCases) { q in
                    QuadrantListView(quadrant: q).tag(q)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .background(Theme.background)
            .navigationTitle("\(current.code) · \(current.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { current = start }
    }
}

struct QuadrantListView: View {
    let quadrant: Quadrant
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var confirmArchiveAll = false

    private var items: [TaskItem] {
        tasks.filter { $0.isOpen && $0.status != .inbox && $0.quadrant == quadrant }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    var body: some View {
        List {
            Section {
                Text(quadrant.guidance).font(.footnote).foregroundStyle(.secondary)
            }
            Section("\(items.count) open") {
                ForEach(items) { task in
                    NavigationLink { TaskDetailView(task: task) } label: { TaskRowView(task: task, showQuadrant: false) }
                        .taskInteractions(task)
                }
            }
            if quadrant == .eliminate && !items.isEmpty {
                Section {
                    Button("Archive all \(items.count)…", role: .destructive) { confirmArchiveAll = true }
                } footer: {
                    Text("Nothing in Q4 is ever removed automatically. Archived items stay in your history.")
                }
            }
            Color.clear.frame(height: 40).listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog("Archive \(items.count) tasks?", isPresented: $confirmArchiveAll, titleVisibility: .visible) {
            Button("Archive", role: .destructive) {
                for t in items { TaskActions.archive(t, in: context) }
            }
        }
    }
}

/// Confirms (or declines) urgency escalations one by one.
struct EscalationReviewSheet: View {
    let tasks: [TaskItem]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(tasks) { task in
                let target = EisenhowerClassifier.urgencyEscalation(current: task.quadrant, dueDate: task.dueDate,
                                                                    hasDueTime: task.hasDueTime,
                                                                    isSafetyCritical: task.category.isSafetyCritical,
                                                                    now: Date(), calendar: .current) ?? task.quadrant
                VStack(alignment: .leading, spacing: 8) {
                    TaskRowView(task: task)
                    HStack {
                        Button("Move to \(target.code) \(target.title)") { TaskActions.setQuadrant(task, target, in: context) }
                            .buttonStyle(.borderedProminent)
                        Button("Keep \(task.quadrant.code)") { TaskActions.setQuadrant(task, task.quadrant, in: context) }
                            .buttonStyle(.bordered)
                    }
                    .font(.subheadline)
                }
            }
            .navigationTitle("Due soon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct MatrixGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Urgency and importance are separate. A close deadline makes something urgent — never automatically important. Safety and compliance work is always important, even when it's due far away.")
                }
                ForEach(Quadrant.allCases) { q in
                    Section {
                        Text(q.guidance)
                    } header: {
                        Label("\(q.code) · \(q.title) — \(q.subtitle)", systemImage: q.systemImage).foregroundStyle(Theme.color(for: q))
                    }
                }
                Section {
                    Text("Suggestions are made on your iPhone from the words you use, due dates, categories and priority. You can always override them, and a manual choice sticks.")
                }
            }
            .navigationTitle("The Matrix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
