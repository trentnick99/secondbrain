import SwiftData
import SwiftUI
import SecondBrainCore

/// Full task editor: details, schedule, reminder, Eisenhower classification, associate, follow-up
/// details, delegation, subtasks, notes, calendar link, recurrence and history.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var originalDue: Date?
    @State private var didCaptureOriginal = false
    @State private var newSubtask = ""
    @State private var confirmDelete = false
    @State private var showReschedule = false
    @State private var pendingQuadrant: Quadrant?
    @State private var calendarMessage: String?
    @State private var showSeries = false
    @State private var showDelegate = false

    var body: some View {
        Form {
            titleSection
            statusSection
            scheduleSection
            matrixSection
            peopleSection
            if task.kind == .followUp { followUpSection }
            TermsMentionedSection(text: task.title + "\n" + task.details)
            subtasksSection
            relatedSection
            calendarSection
            if task.isCompleted || !task.completionNotes.isEmpty {
                Section("Completion notes") {
                    TextField("What happened?", text: $task.completionNotes, axis: .vertical).lineLimit(2...6)
                }
            }
            historySection
            actionsSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(task.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(task.isCompleted ? "Reopen" : "Complete") {
                    if task.isCompleted { TaskActions.reopen(task, in: context) } else { TaskActions.complete(task, in: context) }
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            if !didCaptureOriginal { originalDue = task.dueDate; didCaptureOriginal = true }
        }
        .onDisappear {
            TaskActions.noteDueChange(task, from: originalDue, in: context)
            TaskActions.touch(task, in: context)
        }
        .onChange(of: task.reminderDate) { _, _ in NotificationService.shared.requestResync() }
        .onChange(of: task.dueDate) { _, _ in
            TaskActions.reclassifyIfAutomatic(task)
            NotificationService.shared.requestResync()
        }
        .sheet(isPresented: $showReschedule) { RescheduleSheet(task: task).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showDelegate) { DelegateSheet(task: task) }
        .sheet(isPresented: $showSeries) {
            if let id = task.seriesID, let series = RecurrenceService.series(with: id, in: context) {
                NavigationStack { SeriesEditorView(series: series) }
            }
        }
        .safetyMoveConfirmation(task: task, pending: $pendingQuadrant)
        .confirmationDialog("Delete this task permanently?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                TaskActions.delete(task, in: context)
                dismiss()
            }
            Button("Archive instead") { TaskActions.archive(task, in: context) }
        } message: {
            Text("Archiving keeps the history. Deleting can't be undone.")
        }
        .alert("Calendar", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(calendarMessage ?? "")
        }
    }

    // MARK: Sections

    private var titleSection: some View {
        Section {
            TextField("Title", text: $task.title, axis: .vertical)
                .font(.headline)
                .accessibilityIdentifier("taskTitleField")
            TextField("Description", text: $task.details, axis: .vertical)
                .lineLimit(2...8)
            SensitiveContentNotice(text: task.title + "\n" + task.details)
            Picker("Type", selection: $task.kind) {
                ForEach(TaskKind.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
        }
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: Binding(get: { task.status }, set: { TaskActions.setStatus(task, $0, in: context) })) {
                ForEach(TaskStatus.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Picker("Priority", selection: $task.priority) {
                ForEach(TaskPriority.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Picker("Category", selection: $task.category) {
                ForEach(TaskCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            Toggle(isOn: Binding(
                get: { task.focusDate.map { Calendar.current.isDateInToday($0) } ?? false },
                set: { _ in
                    if !TaskActions.toggleFocus(task, in: context) { router.showToast("You already have 3 priorities today") }
                })) {
                Label("One of today's top 3", systemImage: "star")
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            Toggle("Due date", isOn: Binding(
                get: { task.dueDate != nil },
                set: { on in
                    task.dueDate = on ? (task.dueDate ?? Calendar.current.startOfDay(for: Date())) : nil
                    if !on { task.hasDueTime = false }
                }))
            if task.dueDate != nil {
                Toggle("Specific time", isOn: $task.hasDueTime)
                DatePicker("Due", selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }),
                           displayedComponents: task.hasDueTime ? [.date, .hourAndMinute] : [.date])
                Button("Reschedule…") { showReschedule = true }
            }
            Toggle("Reminder", isOn: Binding(
                get: { task.reminderDate != nil },
                set: { on in task.reminderDate = on ? (task.reminderDate ?? suggestedReminder) : nil }))
            if task.reminderDate != nil {
                DatePicker("Remind at", selection: Binding(get: { task.reminderDate ?? Date() }, set: { task.reminderDate = $0 }),
                           displayedComponents: [.date, .hourAndMinute])
                Menu {
                    ForEach(SnoozeOption.allCases) { option in
                        Button(option.title) { TaskActions.snooze(task, option: option, in: context) }
                    }
                } label: {
                    Label("Snooze", systemImage: "bell.badge")
                }
            }
            if let id = task.seriesID, let series = RecurrenceService.series(with: id, in: context) {
                Button {
                    showSeries = true
                } label: {
                    LabeledContent {
                        Text(series.summary()).foregroundStyle(.secondary)
                    } label: {
                        Label("Repeats", systemImage: "repeat")
                    }
                }
            }
        } header: {
            Text("When")
        } footer: {
            if task.rescheduleCount >= WeeklyReview.postponedThreshold {
                Text("Postponed \(task.rescheduleCount) times — consider doing, delegating or dropping it.")
            }
        }
    }

    private var matrixSection: some View {
        Section {
            QuadrantPicker(quadrant: Binding(
                get: { task.quadrant },
                set: { q in
                    if task.category.isSafetyCritical && !q.isImportant {
                        pendingQuadrant = q
                    } else {
                        TaskActions.setQuadrant(task, q, in: context)
                    }
                }))
            let suggestion = TaskActions.classification(for: task)
            if task.classificationIsManual {
                HStack {
                    Text("Suggested: \(suggestion.quadrant.code) \(suggestion.quadrant.title)").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button("Use suggestion") { TaskActions.useSuggestedQuadrant(task, in: context) }.font(.footnote)
                }
            }
            ForEach(task.classificationIsManual ? ["Set manually"] : task.reasons, id: \.self) { reason in
                Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Eisenhower Matrix")
        } footer: {
            Text(task.quadrant.guidance)
        }
    }

    private var peopleSection: some View {
        Section("People") {
            Picker("Associate", selection: Binding(
                get: { task.associate?.id },
                set: { id in
                    task.associate = associates.first { $0.id == id }
                    if let person = task.associate, task.department.isEmpty { task.department = person.department }
                })) {
                Text("None").tag(UUID?.none)
                ForEach(associates.filter { !$0.isArchived || $0.id == task.associate?.id }) { person in
                    Text(person.name).tag(Optional(person.id))
                }
            }
            Picker("Department", selection: $task.department) {
                Text("None").tag("")
                ForEach(DepartmentLexicon.allNames, id: \.self) { Text($0).tag($0) }
                if !task.department.isEmpty && !DepartmentLexicon.allNames.contains(task.department) {
                    Text(task.department).tag(task.department)
                }
            }
            Button { showDelegate = true } label: {
                Label(task.delegatedTo.isEmpty ? "Delegate to a team lead…" : "Change who it's delegated to…", systemImage: "person.badge.plus")
            }
            TextField("Delegated to", text: Binding(
                get: { task.delegatedTo },
                set: { value in
                    task.delegatedTo = value
                    if !value.isEmpty { task.delegationConfirmed = false }
                }))
            if !task.delegatedTo.isEmpty {
                Toggle("They confirmed they'll do it", isOn: Binding(
                    get: { task.delegationConfirmed },
                    set: { on in
                        if on { TaskActions.confirmDelegation(task, in: context) } else { task.delegationConfirmed = false }
                    }))
            }
            if task.status == .waiting {
                TextField("Waiting on", text: $task.waitingOn)
            }
        }
    }

    private var followUpSection: some View {
        Section("Follow-up") {
            TextField("What they asked", text: $task.request, axis: .vertical)
            TextField("What I committed to", text: $task.commitment, axis: .vertical)
            DatePicker("Conversation", selection: Binding(get: { task.conversationDate ?? task.createdAt },
                                                          set: { task.conversationDate = $0 }),
                       displayedComponents: [.date])
            let related = relatedFollowUpTasks
            if !related.isEmpty {
                ForEach(related) { t in
                    NavigationLink { TaskDetailView(task: t) } label: { TaskRowView(task: t, showAssociate: false) }
                }
            }
            Button {
                let created = TaskActions.createTask(title: "Next step: \(task.displayTitle)", associate: task.associate,
                                                     linkedFollowUpID: task.id, in: context)
                router.open(.task(created.id))
            } label: {
                Label("Add related task", systemImage: "plus")
            }
        }
    }

    private var subtasksSection: some View {
        Section("Subtasks") {
            ForEach(task.sortedSubtasks) { item in
                HStack {
                    Button {
                        item.isDone.toggle()
                        TaskActions.touch(task, in: context)
                    } label: {
                        Image(systemName: item.isDone ? "checkmark.square.fill" : "square")
                            .foregroundStyle(item.isDone ? Theme.success : .secondary)
                    }
                    .buttonStyle(.borderless)
                    TextField("Subtask", text: Binding(get: { item.text }, set: { item.text = $0 }))
                        .strikethrough(item.isDone)
                    if item.convertedTaskID == nil {
                        Button {
                            TaskActions.convert(item, in: context)
                        } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Convert to task")
                    }
                }
            }
            .onDelete { offsets in
                let items = task.sortedSubtasks
                for index in offsets { context.delete(items[index]) }
                TaskActions.touch(task, in: context)
            }
            HStack {
                TextField("Add subtask", text: $newSubtask)
                    .onSubmit(addSubtask)
                Button("Add", action: addSubtask).disabled(newSubtask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        let notes = task.notes ?? []
        if !notes.isEmpty {
            Section("Notes") {
                ForEach(notes) { note in
                    NavigationLink { NoteEditorView(note: note) } label: {
                        Label(note.displayTitle, systemImage: note.type.systemImage)
                    }
                }
            }
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            if !task.calendarEventID.isEmpty, let event = CalendarService.shared.event(withIdentifier: task.calendarEventID) {
                LabeledContent("Linked event", value: event.title ?? "Event")
            } else if task.dueDate != nil {
                Button {
                    do {
                        task.calendarEventID = try CalendarService.shared.addEvent(for: task)
                        TaskActions.touch(task, in: context)
                        calendarMessage = "Added to your calendar."
                    } catch {
                        calendarMessage = error.localizedDescription
                    }
                } label: {
                    Label("Add to Apple Calendar", systemImage: "calendar.badge.plus")
                }
            } else {
                Text("Give the task a date to add it to your calendar.").font(.footnote).foregroundStyle(.secondary)
            }
            let conflicts = CalendarService.shared.conflicts(for: task)
            if !conflicts.isEmpty {
                Label("Overlaps \(conflicts.map { $0.title ?? "an event" }.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.warning)
            }
        }
    }

    private var historySection: some View {
        Section("History") {
            ForEach(task.sortedActivity.prefix(20)) { event in
                HStack(alignment: .top) {
                    Image(systemName: event.systemImage).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.summary.isEmpty ? event.title : event.summary).font(.subheadline)
                        Text(event.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Created", value: task.createdAt.formatted(date: .abbreviated, time: .shortened))
            if let done = task.completedAt {
                LabeledContent("Completed", value: done.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button { TaskActions.duplicate(task, in: context); router.showToast("Duplicated") } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            if task.status != .archived {
                Button { TaskActions.archive(task, in: context) } label: { Label("Archive", systemImage: "archivebox") }
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete…", systemImage: "trash") }
        }
    }

    // MARK: Helpers

    private var relatedFollowUpTasks: [TaskItem] {
        let id: UUID? = task.id
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.linkedFollowUpID == id })
        return (try? context.fetch(descriptor)) ?? []
    }

    private var suggestedReminder: Date {
        if let due = task.dueDate {
            let candidate = task.hasDueTime ? due : DateMath(calendar: .current).date(on: due, minutes: AppSettings.defaultReminderMinutes)
            if candidate > Date() { return candidate }
        }
        return Date().addingTimeInterval(3600)
    }

    private func addSubtask() {
        let text = newSubtask.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = ChecklistItem(text: text, sortIndex: (task.subtasks?.count ?? 0))
        context.insert(item)
        item.task = task
        newSubtask = ""
        TaskActions.touch(task, in: context)
    }
}
