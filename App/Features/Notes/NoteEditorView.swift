import SwiftData
import SwiftUI
import SecondBrainCore

/// Note editor: title, type, tags, associate, body, checklist (items convert to tasks), linked tasks,
/// and "Find follow-ups" which detects commitments in the text and offers them as tasks.
struct NoteEditorView: View {
    @Bindable var note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var newItem = ""
    @State private var tagsText = ""
    @State private var suggestions: [CommitmentSuggestion] = []
    @State private var showSuggestions = false
    @State private var showLinkTask = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $note.title, axis: .vertical)
                    .font(.title3.weight(.semibold))
                TextField("Write your note…", text: $note.body, axis: .vertical)
                    .lineLimit(6...30)
                    .focused($bodyFocused)
            }

            Section("Checklist") {
                ForEach(note.sortedChecklist) { item in
                    HStack {
                        Button {
                            item.isDone.toggle()
                            note.updatedAt = Date()
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isDone ? Theme.success : .secondary)
                        }
                        .buttonStyle(.borderless)
                        TextField("Item", text: Binding(get: { item.text }, set: { item.text = $0; note.updatedAt = Date() }))
                            .strikethrough(item.isDone)
                        if item.convertedTaskID == nil {
                            Button {
                                let task = TaskActions.convert(item, in: context)
                                router.showToast("Task created: \(task.displayTitle)")
                            } label: { Image(systemName: "arrow.up.right.square") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Convert to task")
                        } else {
                            Image(systemName: "checklist.checked").foregroundStyle(.secondary).accessibilityLabel("Converted to task")
                        }
                    }
                }
                .onDelete { offsets in
                    let items = note.sortedChecklist
                    for i in offsets { context.delete(items[i]) }
                    note.updatedAt = Date()
                }
                HStack {
                    TextField("Add item", text: $newItem).onSubmit(addItem)
                    Button("Add", action: addItem).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Details") {
                Picker("Type", selection: $note.type) {
                    ForEach(NoteType.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Associate", selection: Binding(get: { note.associate?.id }, set: { id in note.associate = associates.first { $0.id == id } })) {
                    Text("None").tag(UUID?.none)
                    ForEach(associates.filter { !$0.isArchived || $0.id == note.associate?.id }) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Department", selection: $note.department) {
                    Text("None").tag("")
                    ForEach(DepartmentLexicon.allNames, id: \.self) { Text($0).tag($0) }
                    if !note.department.isEmpty && !DepartmentLexicon.allNames.contains(note.department) { Text(note.department).tag(note.department) }
                }
                TextField("Tags (comma separated)", text: $tagsText)
                    .textInputAutocapitalization(.never)
                    .onSubmit { note.tags = tagsText.split(separator: ",").map(String.init) }
                Toggle("Pinned", isOn: $note.isPinned)
            }

            Section("Linked tasks") {
                ForEach(note.linkedTasks ?? []) { task in
                    NavigationLink { TaskDetailView(task: task) } label: { TaskRowView(task: task) }
                }
                Button { showLinkTask = true } label: { Label("Link a task", systemImage: "link") }
                Button {
                    let task = TaskActions.createTask(title: note.displayTitle, associate: note.associate, in: context)
                    var links = note.linkedTasks ?? []
                    links.append(task)
                    note.linkedTasks = links
                    TaskActions.save(context)
                    router.showToast("Task created from note")
                } label: { Label("Create task from this note", systemImage: "plus.square") }
            }

            if note.type == .associate || note.associate != nil {
                Section { PrivacyReminder() }
            }

            Section {
                LabeledContent("Created", value: note.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Edited", value: note.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(note.type.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    note.tags = tagsText.split(separator: ",").map(String.init)
                    suggestions = CommitmentDetector.detect(in: [note.title, note.body].joined(separator: "\n"),
                                                            context: AppSettings.captureContext(knownAssociates: associates.map(\.name)))
                    showSuggestions = true
                } label: {
                    Label("Find follow-ups", systemImage: "sparkles")
                }
            }
        }
        .sheet(isPresented: $showSuggestions) {
            CommitmentSuggestionsSheet(note: note, suggestions: suggestions)
        }
        .sheet(isPresented: $showLinkTask) { LinkTaskSheet(note: note) }
        .onAppear {
            tagsText = note.tagsRaw
            if note.title.isEmpty && note.body.isEmpty { bodyFocused = true }
        }
        .onChange(of: note.body) { _, _ in note.updatedAt = Date() }
        .onChange(of: note.title) { _, _ in note.updatedAt = Date() }
        .onDisappear(perform: finish)
    }

    private func addItem() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let item = ChecklistItem(text: text, sortIndex: note.checklist?.count ?? 0)
        context.insert(item)
        item.note = note
        note.updatedAt = Date()
        newItem = ""
    }

    private func finish() {
        note.tags = tagsText.split(separator: ",").map(String.init)
        let isEmpty = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (note.checklist ?? []).isEmpty
            && (note.linkedTasks ?? []).isEmpty
        if isEmpty {
            context.delete(note)
        } else if let person = note.associate, note.createdAt > Date().addingTimeInterval(-600),
                  !(person.activity ?? []).contains(where: { $0.summary == "Note: \(note.displayTitle)" }) {
            TaskActions.logInteraction(.note, "Note: \(note.displayTitle)", associate: person, in: context)
        }
        TaskActions.save(context)
    }
}

/// Lets the person pick which detected commitments become tasks / follow-ups.
struct CommitmentSuggestionsSheet: View {
    let note: Note
    let suggestions: [CommitmentSuggestion]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if suggestions.isEmpty {
                    ContentUnavailableView("No commitments found", systemImage: "sparkles",
                                           description: Text("Lines like “I'll get back to Maria Friday” or “- [ ] order pallets” are detected."))
                } else {
                    Section {
                        ForEach(suggestions) { s in
                            Button {
                                if selected.contains(s.id) { selected.remove(s.id) } else { selected.insert(s.id) }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: selected.contains(s.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(s.id) ? Theme.accent : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(s.parsed.title).font(.subheadline.weight(.medium))
                                        Text(describe(s.parsed)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("Nothing is created until you choose. People not yet in Associates will be added.")
                    }
                }
            }
            .navigationTitle("Found in this note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create \(selected.count)") { create() }.disabled(selected.isEmpty)
                }
            }
            .onAppear { selected = Set(suggestions.map(\.id)) }
        }
    }

    private func describe(_ p: ParsedCapture) -> String {
        var parts = [p.kind.title]
        if let name = p.associateName { parts.append(name) }
        if let due = p.dueDate { parts.append(RelativeDateText.dueText(due: due, hasTime: p.hasDueTime, now: Date(), calendar: .current)) }
        parts.append(p.classification.quadrant.code)
        return parts.joined(separator: " · ")
    }

    private func create() {
        var count = 0
        for s in suggestions where selected.contains(s.id) {
            if case .task(let task)? = CaptureSaver.save(CaptureDraft(parsed: s.parsed), in: context) {
                var links = note.linkedTasks ?? []
                links.append(task)
                note.linkedTasks = links
                count += 1
            }
        }
        TaskActions.save(context)
        router.showToast("Created \(count) item\(count == 1 ? "" : "s")")
        dismiss()
    }
}

struct LinkTaskSheet: View {
    let note: Note
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks.filter { $0.isOpen && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }.prefix(100)) { task in
                    Button {
                        var links = note.linkedTasks ?? []
                        if !links.contains(where: { $0.id == task.id }) { links.append(task) }
                        note.linkedTasks = links
                        TaskActions.save(context)
                        dismiss()
                    } label: { TaskRowView(task: task) }
                    .buttonStyle(.plain)
                }
            }
            .searchable(text: $search)
            .navigationTitle("Link a Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
