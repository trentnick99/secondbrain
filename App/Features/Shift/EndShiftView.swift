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
    @State private var handoffIncludesAssociates = false
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""

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
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(BriefingBuilder.shiftSummary(review))
                }

                if !carryCandidates.isEmpty {
                    Section {
                        Button {
                            confirmCarryAll = true
                        } label: {
                            Label("Carry all \(carryCandidates.count) to next shift (\(AppSettings.nextShiftLabel()))", systemImage: "arrow.right.circle.fill")
                                .font(.headline)
                        }
                        .accessibilityIdentifier("carryAllButton")
                        ForEach(carryCandidates) { task in
                            ShiftItemRow(task: task)
                        }
                    } header: {
                        Text("Unfinished & overdue")
                    } footer: {
                        Text("Swipe right to mark one done, left to move it, or tap ⋯ for a date. Nothing is removed: items you leave alone stay where they are and show as overdue next shift.")
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
                    Text("Suggested priorities for your next shift")
                } footer: {
                    Text("Starred items become your next shift's top 3 when you finish.")
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

                Section {
                    let handoff = ShiftHandoff.text(review: review, role: RoleStorage.decode(roleJSON),
                                                    includeAssociateItems: handoffIncludesAssociates,
                                                    note: reflection, now: now, calendar: .current)
                    ShareLink(item: handoff, subject: Text("Shift handoff"), preview: SharePreview("Shift handoff")) {
                        Label("Share handoff", systemImage: "square.and.arrow.up")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("shareHandoffButton")
                    Toggle("Include associate follow-ups", isOn: $handoffIncludesAssociates)
                    Text(handoff)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                } header: {
                    Text("Hand off to the next coach")
                } footer: {
                    Text("Send what's still open to the next coach or overnight by text or email. Your notes above are included. Associate follow-ups stay out unless you turn them on.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("End My Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish shift") { finish(review: review, items: items) }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Carry \(carryCandidates.count) items to your next shift (\(AppSettings.nextShiftLabel()))?", isPresented: $confirmCarryAll, titleVisibility: .visible) {
                Button("Carry forward") {
                    TaskActions.carryForward(carryCandidates, to: AppSettings.nextShiftDay(), in: context)
                    carriedCount += carryCandidates.count
                    router.showToast("Carried \(carryCandidates.count) to \(AppSettings.nextShiftLabel())")
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
        let tomorrow = AppSettings.nextShiftDay()
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

/// One unfinished item with explicit choices: complete, next shift, pick a date, or leave it.
/// The choices are swipe actions and a ⋯ menu, so a long list stays readable.
struct ShiftItemRow: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @State private var showReschedule = false
    @State private var completed = 0

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TaskRowView(task: task)
            Menu {
                Button { complete() } label: { Label("Done", systemImage: "checkmark") }
                Button { moveToNextShift() } label: { Label("Next shift (\(AppSettings.nextShiftLabel()))", systemImage: "sunrise") }
                Button { showReschedule = true } label: { Label("Pick a date…", systemImage: "calendar") }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Choices for \(task.displayTitle)")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { complete() } label: { Label("Done", systemImage: "checkmark") }.tint(Theme.success)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { moveToNextShift() } label: { Label("Next shift", systemImage: "sunrise") }.tint(Theme.accent)
            Button { showReschedule = true } label: { Label("Pick date", systemImage: "calendar") }
        }
        .sensoryFeedback(.success, trigger: completed)
        .sheet(isPresented: $showReschedule) { RescheduleSheet(task: task).presentationDetents([.medium, .large]) }
    }

    private func complete() {
        TaskActions.complete(task, in: context)
        completed += 1
    }

    private func moveToNextShift() {
        TaskActions.carryForward([task], to: AppSettings.nextShiftDay(), in: context)
    }
}
