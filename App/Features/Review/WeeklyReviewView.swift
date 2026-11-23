import SwiftData
import SwiftUI
import SecondBrainCore

/// Weekly review: completion, overdue work, repeatedly postponed tasks, stale inbox, long waits,
/// and items that may no longer be needed. Every change is an explicit choice.
struct WeeklyReviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query(sort: \ShiftLog.day, order: .reverse) private var shiftLogs: [ShiftLog]
    @AppStorage(SettingsKey.weekStartsOn, store: AppGroup.defaults) private var weekStartsOn = SettingsDefault.weekStartsOn
    @State private var confirmArchive: TaskItem?

    var body: some View {
        let now = Date()
        let review = WeeklyReview.build(tasks: tasks.map(\.snapshot), now: now, calendar: .current, weekStartsOn: weekStartsOn)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }
        let weekLogs = shiftLogs.filter { $0.day >= review.weekStart && $0.day < review.weekEnd }

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(RelativeDateText.mediumDate(review.weekStart, calendar: .current)) – \(RelativeDateText.mediumDate(review.weekEnd.addingTimeInterval(-1), calendar: .current))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            StatPill(value: review.completed.count, label: "Completed", tint: Theme.success)
                            StatPill(value: review.overdue.count, label: "Overdue", tint: Theme.danger)
                            StatPill(value: review.followUpsResolved.count, label: "Resolved", tint: Theme.accent)
                            StatPill(value: weekLogs.count, label: "Shifts", tint: .secondary)
                        }
                        if let rate = review.completionRate {
                            ProgressView(value: rate) {
                                Text("Completion rate \(Int((rate * 100).rounded()))%").font(.caption)
                            }
                            .tint(Theme.accent)
                        }
                        QuadrantBalance(counts: review.quadrantCounts)
                    }
                    .listRowBackground(Color.clear)
                    Text(BriefingBuilder.weeklySummary(review)).font(.subheadline)
                }

                reviewSection("Overdue", items(review.overdue), footer: "Reschedule realistically, complete, or delegate.")
                postponedSection(items(review.repeatedlyPostponed))
                reviewSection("Inbox items waiting 3+ days", items(review.staleInbox), footer: "Sort these from the Tasks › Inbox filter.")
                reviewSection("Waiting 5+ days", items(review.longWaiting), footer: "Check in with whoever you're waiting on.")
                reviewSection("Open associate follow-ups", items(review.followUpsOutstanding), footer: nil)
                eliminationSection(items(review.eliminationCandidates))

                if !weekLogs.compactMap({ $0.reflection.isEmpty ? nil : $0 }).isEmpty {
                    Section("Shift notes") {
                        ForEach(weekLogs.filter { !$0.reflection.isEmpty }) { log in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(RelativeDateText.mediumDate(log.day, calendar: .current)).font(.caption).foregroundStyle(.secondary)
                                Text(log.reflection).font(.subheadline)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Archive this task?", isPresented: Binding(get: { confirmArchive != nil }, set: { if !$0 { confirmArchive = nil } }),
                                titleVisibility: .visible) {
                Button("Archive") {
                    if let t = confirmArchive { TaskActions.archive(t, in: context) }
                    confirmArchive = nil
                }
            } message: {
                Text("It stays in your history and can be restored from Tasks › Archived.")
            }
        }
    }

    @ViewBuilder
    private func reviewSection(_ title: String, _ list: [TaskItem], footer: String?) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list.prefix(10)) { task in
                    NavigationLink { TaskDetailView(task: task) } label: { TaskRowView(task: task) }
                        .taskInteractions(task)
                }
            } header: {
                Text("\(title) · \(list.count)")
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    @ViewBuilder
    private func postponedSection(_ list: [TaskItem]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        TaskRowView(task: task)
                        Text("Postponed \(task.rescheduleCount) times").font(.caption).foregroundStyle(Theme.warning)
                        HStack(spacing: 8) {
                            Button("Do today") {
                                TaskActions.reschedule(task, to: Date(), in: context)
                                _ = TaskActions.toggleFocus(task, in: context)
                            }
                            Button("Delegate") { TaskActions.setQuadrant(task, .delegate, in: context) }
                            Button("Archive") { confirmArchive = task }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            } header: {
                Text("Repeatedly postponed · \(list.count)")
            } footer: {
                Text("Decide: do it, hand it off, or let it go.")
            }
        }
    }

    @ViewBuilder
    private func eliminationSection(_ list: [TaskItem]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list.prefix(10)) { task in
                    HStack {
                        TaskRowView(task: task)
                        Button("Archive") { confirmArchive = task }.buttonStyle(.bordered).font(.caption)
                    }
                }
            } header: {
                Text("May no longer be needed · \(list.count)")
            } footer: {
                Text("Q4 items and stale undated tasks. Nothing is archived or deleted without your OK. Safety items are never listed here.")
            }
        }
    }
}

struct QuadrantBalance: View {
    let counts: [Quadrant: Int]

    var body: some View {
        let total = max(1, counts.values.reduce(0, +))
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Quadrant.allCases) { q in
                        let n = counts[q] ?? 0
                        if n > 0 {
                            Rectangle()
                                .fill(Theme.color(for: q))
                                .frame(width: max(4, geo.size.width * CGFloat(n) / CGFloat(total)))
                        }
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            HStack(spacing: 10) {
                ForEach(Quadrant.allCases) { q in
                    Text("\(q.code) \(counts[q] ?? 0)").font(.caption2.weight(.semibold)).foregroundStyle(Theme.color(for: q))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Quadrant.allCases.map { "\($0.code) \(counts[$0] ?? 0)" }.joined(separator: ", "))
    }
}
