import SwiftData
import SwiftUI
import SecondBrainCore

/// End My Shift: what got done, what's left, what you owe people, and what to tackle tomorrow.
/// Nothing unfinished is discarded — every item is carried, rescheduled, completed or left as is by choice.
struct EndShiftView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @State private var reflection = ""
    @State private var tomorrowFocus: Set<UUID> = []
    @State private var carriedCount = 0
    @State private var confirmCarryAll = false
    @State private var showCompleted = false
    @State private var didInitFocus = false

    var body: some View {
        let now = Date()
        let review = ShiftReview.build(tasks: tasks.map(\.snapshot), now: now, calendar: .current)
        let lookup = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items: ([TaskSnapshot]) -> [TaskItem] = { snaps in snaps.compactMap { lookup[$0.id] } }
        let carryCandidates = items(review.carryForwardCandidates)

        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        StatPill(value: review.completedToday.count, label: "Completed", tint: Theme.success)
                        StatPill(value: carryCandidates.count, label: "Unfinished", tint: Theme.warning)
                        StatPill(value: review.outstandingCommitments.count, label: "Commitments", tint: Theme.accent)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Text(BriefingBuilder.shiftSummary(review)).font(.subheadline).foregroundStyle(.secondary)
                }

                if !carryCandidates.isEmpty {
                    Section {
                        ForEach(carryCandidates) { task in
                            ShiftItemRow(task: task)
                        }
                        Button {
                            confirmCarryAll = true
                        } label: {
                            Label("Carry all \(carryCandidates.count) to tomorrow", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("carryAllButton")
                    } header: {
                        Text("Unfinished & overdue")
                    } footer: {
                        Text("Nothing is removed. Items you leave alone stay where they are and show as overdue tomorrow.")
                    }
                }

                shiftSection("Outstanding associate commitments", items(review.outstandingCommitments).filter { t in !carryCandidates.contains { $0.id == t.id } })
                delegatedSection(items(review.awaitingConfirmation))
                shiftSection("Upcoming deadlines", items(review.upcomingDeadlines))
                shiftSection("Important Q2 work", items(review.importantQ2))

                Section {
                    ForEach(items(review.suggestedTomorrow)) { task in
                        Button {
                            if tomorrowFocus.contains(task.id) { tomorrowFocus.remove(task.id) }
                            else if tomorrowFocus.count < 3 { tomorrowFocus.insert(task.id) }
                        } label: {
                            HStack {
                                Image(systemName: tomorrowFocus.contains(task.id) ? "star.fill" : "star")
                                    .foregroundStyle(Theme.warning)
                                TaskRowView(task: task)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Suggested priorities for tomorrow")
                } footer: {
                    Text("Starred items become tomorrow's top 3 when you finish.")
                }

                Section("Completed today · \(review.completedToday.count)") {
                    if showCompleted {
                        ForEach(items(review.completedToday)) { TaskRowView(task: $0, showQuadrant: false) }
                    } else if !review.completedToday.isEmpty {
                        Button("Show completed") { showCompleted = true }
                    } else {
                        Text("Nothing marked complete today.").foregroundStyle(.secondary)
                    }
                }

                Section("Notes for tomorrow (optional)") {
                    TextField("Anything to remember?", text: $reflection, axis: .vertical).lineLimit(2...5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("End My Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { finish(review: review, items: items) }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Carry \(carryCandidates.count) items to tomorrow?", isPresented: $confirmCarryAll, titleVisibility: .visible) {
                Button("Carry forward") {
                    TaskActions.carryForward(carryCandidates, to: Rescheduler.carryForwardDay(now: Date(), calendar: .current), in: context)
                    carriedCount += carryCandidates.count
                    router.showToast("Carried \(carryCandidates.count) to tomorrow")
                }
            } message: {
                Text("Each keeps its time of day and reminder offset. Postponements are counted for your weekly review.")
            }
            .onAppear {
                guard !didInitFocus else { return }
                didInitFocus = true
                tomorrowFocus = Set(review.suggestedTomorrow.prefix(3).map(\.id))
            }
        }
    }

    @ViewBuilder
    private func shiftSection(_ title: String, _ list: [TaskItem]) -> some View {
        if !list.isEmpty {
            Section("\(title) · \(list.count)") {
                ForEach(list.prefix(8)) { task in
                    NavigationLink { TaskDetailView(task: task) } label: { TaskRowView(task: task) }
                        .taskInteractions(task)
                }
            }
        }
    }

    @ViewBuilder
    private func delegatedSection(_ list: [TaskItem]) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        TaskRowView(task: task)
                        if !task.delegatedTo.isEmpty && !task.delegationConfirmed {
                            Button("\(task.delegatedTo) confirmed") { TaskActions.confirmDelegation(task, in: context) }
                                .buttonStyle(.bordered)
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text("Delegated — awaiting confirmation · \(list.count)")
            } footer: {
                Text("Hand-offs are never assumed accepted.")
            }
        }
    }

    private func finish(review: ShiftReview, items: ([TaskSnapshot]) -> [TaskItem]) {
        let tomorrow = Rescheduler.carryForwardDay(now: Date(), calendar: .current)
        let focus = tasks.filter { tomorrowFocus.contains($0.id) && $0.isOpen }
        if !focus.isEmpty { TaskActions.setFocus(focus, on: tomorrow, in: context) }

        let log = ShiftLog(day: Calendar.current.startOfDay(for: Date()))
        log.completedCount = review.completedToday.count
        log.carriedForwardCount = carriedCount
        log.openCommitments = review.outstandingCommitments.count
        log.reflection = reflection
        context.insert(log)

        if !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let note = Note(title: "Shift notes · \(RelativeDateText.mediumDate(Date(), calendar: .current))", body: reflection, type: .general)
            note.tags = ["shift"]
            context.insert(note)
        }
        AppGroup.defaults.set(NotificationPlanner.dayKey(Date(), calendar: .current), forKey: SettingsKey.lastShiftEndedDay)
        TaskActions.save(context)
        router.showToast("Shift wrapped · \(review.completedToday.count) done")
        dismiss()
    }
}

/// One unfinished item with explicit choices: complete, tomorrow, pick a date, or leave it.
struct ShiftItemRow: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @State private var showReschedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskRowView(task: task)
            HStack(spacing: 8) {
                Button {
                    TaskActions.complete(task, in: context)
                } label: { Label("Done", systemImage: "checkmark") }
                    .buttonStyle(.bordered).tint(Theme.success)
                Button {
                    TaskActions.carryForward([task], to: Rescheduler.carryForwardDay(now: Date(), calendar: .current), in: context)
                } label: { Label("Tomorrow", systemImage: "sunrise") }
                    .buttonStyle(.bordered).tint(Theme.accent)
                Button {
                    showReschedule = true
                } label: { Label("Pick date", systemImage: "calendar") }
                    .buttonStyle(.bordered)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showReschedule) { RescheduleSheet(task: task).presentationDetents([.medium, .large]) }
    }
}
