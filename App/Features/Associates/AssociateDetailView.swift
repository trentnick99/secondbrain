import SwiftData
import SwiftUI
import SecondBrainCore

struct AssociateDetailView: View {
    @Bindable var associate: Associate
    @Environment(\.modelContext) private var context
    @State private var showFollowUp = false
    @State private var showEdit = false
    @State private var showLog = false
    @State private var noteToEdit: Note?

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(associate.initials)
                        .font(.title2.weight(.bold))
                        .frame(width: 56, height: 56)
                        .background(Theme.accent.opacity(0.18), in: Circle())
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(associate.name).font(.title3.weight(.semibold))
                        Text([associate.role, associate.department].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let last = associate.lastInteractionAt {
                            Text("Last interaction \(RelativeDateText.dayLabel(for: last, now: Date(), calendar: .current))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !associate.profileNote.isEmpty {
                    Text(associate.profileNote).font(.subheadline)
                }
                HStack(spacing: 10) {
                    actionButton("Follow-up", "person.crop.circle.badge.clock") { showFollowUp = true }
                    actionButton("Log talk", "bubble.left.and.bubble.right") { showLog = true }
                    actionButton("Note", "note.text.badge.plus") { noteToEdit = newNote() }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            taskSection("Open follow-ups", associate.openFollowUps, empty: "No open follow-ups.")
            taskSection("Other open tasks", associate.otherOpenTasks, empty: nil)

            if !associate.sortedNotes.isEmpty {
                Section("Notes") {
                    ForEach(associate.sortedNotes) { note in
                        NavigationLink { NoteEditorView(note: note) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.displayTitle)
                                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Interaction history") {
                if associate.history.isEmpty {
                    Text("Conversations, requests and resolved follow-ups will appear here.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(associate.history.prefix(30)) { event in
                    HStack(alignment: .top) {
                        Image(systemName: event.systemImage).foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.summary.isEmpty ? event.title : event.summary).font(.subheadline)
                            Text("\(event.title) · \(event.date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            taskSection("Resolved", Array(associate.resolvedFollowUps.prefix(15)), empty: nil)

            Section { PrivacyReminder() }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(associate.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("Edit") { showEdit = true } }
        }
        .sheet(isPresented: $showFollowUp) { FollowUpEditorView(associate: associate) }
        .sheet(isPresented: $showEdit) { AssociateEditorView(associate: associate) }
        .sheet(isPresented: $showLog) { LogInteractionSheet(associate: associate) }
        .sheet(item: $noteToEdit) { note in
            NavigationStack { NoteEditorView(note: note) }
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, _ items: [TaskItem], empty: String?) -> some View {
        if !items.isEmpty || empty != nil {
            Section(title) {
                if items.isEmpty, let empty {
                    Text(empty).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(items) { t in
                    NavigationLink { TaskDetailView(task: t) } label: { TaskRowView(task: t, showAssociate: false) }
                        .taskInteractions(t)
                }
            }
        }
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func newNote() -> Note {
        let note = Note(title: "", body: "", type: .associate)
        note.department = associate.department
        context.insert(note)
        note.associate = associate
        return note
    }
}

struct AssociateEditorView: View {
    let associate: Associate?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var department = ""
    @State private var role = ""
    @State private var profileNote = ""
    @State private var isArchived = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name or identifier", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Role (optional)", text: $role)
                    Picker("Department", selection: $department) {
                        Text("None").tag("")
                        ForEach(DepartmentLexicon.allNames, id: \.self) { Text($0).tag($0) }
                        if !department.isEmpty && !DepartmentLexicon.allNames.contains(department) { Text(department).tag(department) }
                    }
                }
                Section {
                    TextField("Short, non-sensitive context", text: $profileNote, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text("Context")
                } footer: {
                    PrivacyReminder()
                }
                if associate != nil {
                    Section {
                        Toggle("Archived", isOn: $isArchived)
                    } footer: {
                        Text("Archived people are hidden from lists; their history is kept.")
                    }
                }
            }
            .navigationTitle(associate == nil ? "New Associate" : "Edit Associate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let a = associate {
                    name = a.name; department = a.department; role = a.role; profileNote = a.profileNote; isArchived = a.isArchived
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let target: Associate
        if let associate {
            target = associate
        } else if let existing = TaskActions.associate(named: trimmed, createIfMissing: false, in: context) {
            target = existing
        } else {
            target = Associate(name: trimmed)
            context.insert(target)
        }
        target.name = trimmed
        target.department = department
        target.role = role
        target.profileNote = profileNote
        target.isArchived = isArchived
        target.updatedAt = Date()
        TaskActions.save(context)
        dismiss()
    }
}

/// Records an associate request and what you committed to.
struct FollowUpEditorView: View {
    let associate: Associate?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var personID: UUID?
    @State private var newPerson = ""
    @State private var request = ""
    @State private var commitment = ""
    @State private var conversationDate = Date()
    @State private var followUpDate: Date?
    @State private var remind = true
    @State private var priority: TaskPriority = .normal

    var body: some View {
        NavigationStack {
            Form {
                Section("Associate") {
                    Picker("Person", selection: $personID) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(associates.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if personID == nil {
                        TextField("Or type a new name", text: $newPerson).textInputAutocapitalization(.words)
                    }
                }
                Section("Conversation") {
                    TextField("What did they ask for?", text: $request, axis: .vertical).lineLimit(2...5)
                    TextField("What did you commit to?", text: $commitment, axis: .vertical).lineLimit(1...4)
                    DatePicker("When", selection: $conversationDate, in: ...Date(), displayedComponents: [.date])
                }
                Section {
                    QuickDateChips(date: $followUpDate)
                    if followUpDate != nil {
                        DatePicker("Follow up on", selection: Binding(get: { followUpDate ?? Date() }, set: { followUpDate = $0 }),
                                   displayedComponents: [.date])
                        Toggle("Remind me that morning", isOn: $remind)
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Follow up")
                } footer: {
                    Text("No date is set unless you choose one.")
                }
                Section { PrivacyReminder() }
            }
            .navigationTitle("New Follow-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
            .onAppear { personID = associate?.id }
        }
    }

    private var canSave: Bool {
        !request.trimmingCharacters(in: .whitespaces).isEmpty && (personID != nil || !newPerson.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func save() {
        let person: Associate?
        if let id = personID {
            person = associates.first { $0.id == id }
        } else {
            person = TaskActions.associate(named: newPerson, createIfMissing: true, in: context)
        }
        let title = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(title: title, kind: .followUp)
        task.request = title
        task.commitment = commitment
        task.conversationDate = conversationDate
        task.priority = priority
        task.category = .people
        if let date = followUpDate {
            task.dueDate = Calendar.current.startOfDay(for: date)
            if remind {
                let minutes = AppSettings.effectiveDefaultReminderMinutes ?? SettingsDefault.defaultReminderMinutes
                let reminder = DateMath(calendar: .current).date(on: date, minutes: minutes)
                task.reminderDate = reminder > Date() ? reminder : nil
            }
        }
        context.insert(task)
        task.associate = person
        if let person { task.department = person.department }
        TaskActions.apply(TaskActions.classification(for: task), to: task)
        TaskActions.log(.created, "Follow-up recorded", task: task, in: context)
        if let person {
            TaskActions.logInteraction(.request, title, associate: person, task: task, in: context, date: conversationDate)
        }
        TaskActions.save(context)
        router.showToast("Follow-up saved")
        dismiss()
    }
}

struct LogInteractionSheet: View {
    let associate: Associate
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var kind: InteractionKind = .conversation
    @State private var summary = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) {
                    ForEach([InteractionKind.conversation, .request, .followUp, .note]) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                TextField("Summary", text: $summary, axis: .vertical).lineLimit(2...6)
                DatePicker("When", selection: $date, in: ...Date())
                Section { PrivacyReminder() }
            }
            .navigationTitle("Log Interaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TaskActions.logInteraction(kind, summary, associate: associate, in: context, date: date)
                        TaskActions.save(context)
                        dismiss()
                    }
                    .disabled(summary.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
