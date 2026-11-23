import SwiftData
import SwiftUI
import SecondBrainCore

/// Standard swipe actions and context menu for task rows (complete, tomorrow, reschedule, snooze,
/// move quadrant, top 3, delegate, duplicate, archive, delete-with-confirmation).
struct TaskInteractions: ViewModifier {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var showReschedule = false
    @State private var showDelegate = false
    @State private var confirmDelete = false
    @State private var pendingQuadrant: Quadrant?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if task.isOpen {
                    Button {
                        TaskActions.complete(task, in: context)
                    } label: { Label("Complete", systemImage: "checkmark") }
                        .tint(Theme.success)
                } else {
                    Button {
                        TaskActions.reopen(task, in: context)
                    } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
                        .tint(.gray)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if task.isOpen {
                    Button {
                        TaskActions.reschedule(task, to: Rescheduler.carryForwardDay(now: Date(), calendar: .current), in: context)
                        router.showToast("Moved to tomorrow")
                    } label: { Label("Tomorrow", systemImage: "sunrise") }
                        .tint(Theme.accent)
                    Button {
                        showReschedule = true
                    } label: { Label("Reschedule", systemImage: "calendar") }
                        .tint(.indigo)
                }
            }
            .contextMenu { menu }
            .sheet(isPresented: $showReschedule) {
                RescheduleSheet(task: task)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showDelegate) { DelegateSheet(task: task) }
            .confirmationDialog("Delete this task permanently?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { TaskActions.delete(task, in: context) }
                Button("Archive instead") { TaskActions.archive(task, in: context) }
            } message: {
                Text("Archiving keeps it in your history. Deleting can't be undone.")
            }
            .safetyMoveConfirmation(task: task, pending: $pendingQuadrant)
    }

    @ViewBuilder
    private var menu: some View {
        if task.isOpen {
            Button { TaskActions.complete(task, in: context) } label: { Label("Complete", systemImage: "checkmark.circle") }
            Menu {
                ForEach(SnoozeOption.allCases) { option in
                    Button(option.title) { TaskActions.snooze(task, option: option, in: context) }
                }
            } label: { Label("Snooze Reminder", systemImage: "bell.badge") }
            Button { showReschedule = true } label: { Label("Reschedule…", systemImage: "calendar") }
            Menu {
                ForEach(Quadrant.allCases) { q in
                    Button {
                        if task.category.isSafetyCritical && !q.isImportant {
                            pendingQuadrant = q
                        } else {
                            TaskActions.setQuadrant(task, q, in: context)
                        }
                    } label: { Label("\(q.code) · \(q.title)", systemImage: q.systemImage) }
                }
            } label: { Label("Move to Quadrant", systemImage: "square.grid.2x2") }
            Button {
                if !TaskActions.toggleFocus(task, in: context) { router.showToast("You already have 3 priorities today") }
            } label: {
                let focused = task.focusDate.map { Calendar.current.isDateInToday($0) } ?? false
                Label(focused ? "Remove from Top 3" : "Add to Today's Top 3", systemImage: focused ? "star.slash" : "star")
            }
            if task.delegatedTo.isEmpty {
                Button { showDelegate = true } label: { Label("Delegate…", systemImage: "person.badge.plus") }
            } else if !task.delegationConfirmed {
                Button { TaskActions.confirmDelegation(task, in: context) } label: {
                    Label("Confirm \(task.delegatedTo) Accepted", systemImage: "person.fill.checkmark")
                }
            }
        } else {
            Button { TaskActions.reopen(task, in: context) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
        }
        Button { router.open(.task(task.id)) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
        Button { TaskActions.duplicate(task, in: context) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        if task.status != .archived {
            Button { TaskActions.archive(task, in: context) } label: { Label("Archive", systemImage: "archivebox") }
        }
        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete…", systemImage: "trash") }
    }
}

extension View {
    func taskInteractions(_ task: TaskItem) -> some View { modifier(TaskInteractions(task: task)) }
}

/// Asks before moving a safety or compliance task into a "not important" quadrant.
struct SafetyMoveConfirmation: ViewModifier {
    let task: TaskItem
    @Binding var pending: Quadrant?
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Safety & compliance work is always treated as important.",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let q = pending {
                Button("Move to \(q.code) \(q.title) anyway") {
                    TaskActions.setQuadrant(task, q, in: context)
                    pending = nil
                }
                Button("Keep it important") {
                    let keep = Quadrant(urgent: q.isUrgent, important: true)
                    TaskActions.setQuadrant(task, keep, in: context)
                    pending = nil
                }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text("A distant deadline doesn't make it unimportant.")
        }
    }
}

extension View {
    func safetyMoveConfirmation(task: TaskItem, pending: Binding<Quadrant?>) -> some View {
        modifier(SafetyMoveConfirmation(task: task, pending: pending))
    }
}

/// Quick reschedule choices plus a full date picker.
struct RescheduleSheet: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var customDate = Date()
    @State private var includeTime = false

    var body: some View {
        NavigationStack {
            List {
                Section("Quick") {
                    ForEach(quickDays) { option in
                        Button {
                            TaskActions.reschedule(task, to: option.date, in: context)
                            dismiss()
                        } label: {
                            HStack {
                                Text(option.label)
                                Spacer()
                                Text(RelativeDateText.mediumDate(option.date, calendar: .current)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Pick a date") {
                    Toggle("Include time", isOn: $includeTime)
                    DatePicker("Date", selection: $customDate,
                               displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                        .datePickerStyle(.graphical)
                    Button("Move to this date") {
                        if includeTime {
                            let original = task.dueDate
                            TaskActions.setDue(task, date: customDate, hasTime: true, in: context)
                            if task.reminderDate == nil || (task.reminderDate ?? .distantPast) < Date() {
                                task.reminderDate = customDate > Date() ? customDate : nil
                            }
                            TaskActions.noteDueChange(task, from: original, in: context)
                            TaskActions.touch(task, in: context)
                        } else {
                            TaskActions.reschedule(task, to: customDate, in: context)
                        }
                        dismiss()
                    }
                }
                if task.dueDate != nil {
                    Section {
                        Button("Remove due date", role: .destructive) {
                            TaskActions.setDue(task, date: nil, hasTime: false, in: context)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear {
                customDate = task.dueDate ?? Date()
                includeTime = task.hasDueTime
            }
        }
    }

    struct QuickDay: Identifiable {
        let label: String
        let date: Date
        var id: String { label }
    }

    private var quickDays: [QuickDay] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func add(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: today) ?? today }
        let weekStart = DateMath(calendar: cal).startOfWeek(containing: today, firstWeekday: AppSettings.weekStartsOn)
        let nextWeek = cal.date(byAdding: .day, value: 7, to: weekStart) ?? add(7)
        let nextWeekWorkday = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: nextWeek) }
            .first { (2...6).contains(cal.component(.weekday, from: $0)) } ?? nextWeek
        return [QuickDay(label: "Today", date: today), QuickDay(label: "Tomorrow", date: add(1)),
                QuickDay(label: "In 2 days", date: add(2)), QuickDay(label: "Next week", date: nextWeekWorkday)]
    }
}
