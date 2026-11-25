import SwiftUI
import SwiftData
import SecondBrainCore

/// Standards: a reference library of lists. Food safety temperatures and quality checks from public
/// sources, the person's own lists (temperatures on certain items, quality standards, processes), and
/// step lists for store processes like the freezer door or a frozen truck. It filters lists; it never
/// answers questions or writes steps of its own. Works offline.
struct StandardsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.standardLists, store: AppGroup.defaults) private var listsJSON = ""
    @AppStorage(SettingsKey.customGuides, store: AppGroup.defaults) private var oldGuidesJSON = ""
    @State private var query: String

    init(initialQuery: String? = nil) {
        _query = State(initialValue: (initialQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var lists: [StandardList] { StandardListStorage.decode(listsJSON) }
    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            List {
                ForEach(StandardList.Kind.allCases, id: \.self) { kind in
                    section(for: kind)
                }
                if searching && nothingMatches {
                    Section {
                        Text("Nothing matches \"\(query)\". Try other words, or add your own list.")
                            .foregroundStyle(.secondary)
                    }
                }
                if !searching {
                    Section {
                        ForEach(StandardList.Kind.allCases, id: \.self) { kind in
                            NavigationLink(value: StandardEditorRef(id: nil, kind: kind)) {
                                Label("New \(kind.singular)", systemImage: "plus.circle")
                            }
                            .accessibilityIdentifier("newStandard-\(kind.rawValue)")
                        }
                    } header: {
                        Text("Add your own")
                    } footer: {
                        Text("Write down the temperatures, standards and steps your store trained you on. Kept on your phone. Don't include passwords, codes or anyone's personal details.")
                    }
                }
                Section {} footer: { Text(Standards.disclaimer) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search temperatures, standards, processes")
            .navigationTitle("Standards")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ReferenceRef.self) { ref in
                if let reference = Standards.reference(id: ref.id) { ReferenceDetailView(reference: reference) }
            }
            .navigationDestination(for: StandardListRef.self) { ref in
                StandardListDetailView(listID: ref.id)
            }
            .navigationDestination(for: StandardEditorRef.self) { ref in
                StandardListEditor(existing: lists.first { $0.id == ref.id }, kind: ref.kind)
            }
            .navigationDestination(for: GuideRef.self) { ref in
                if let guide = CoachGuides.guide(id: ref.id) { GuideDetailView(guide: guide) }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear(perform: migrateOldGuides)
        }
    }

    // MARK: Sections

    private func references(_ kind: StandardList.Kind) -> [ReferenceList] {
        Standards.references.filter { $0.kind == kind && Standards.matches(query, in: Standards.searchText($0)) }
    }

    private func own(_ kind: StandardList.Kind) -> [StandardList] {
        lists.filter { $0.kind == kind && Standards.matches(query, in: Standards.searchText($0)) }
    }

    private var processes: [CoachGuide] {
        Standards.processes.filter { Standards.matches(query, in: Standards.searchText($0)) }
    }

    private var nothingMatches: Bool {
        StandardList.Kind.allCases.allSatisfy { references($0).isEmpty && own($0).isEmpty } && processes.isEmpty
    }

    @ViewBuilder
    private func section(for kind: StandardList.Kind) -> some View {
        let refs = references(kind)
        let mine = own(kind)
        let guides = kind == .process ? processes : []
        if !(refs.isEmpty && mine.isEmpty && guides.isEmpty) {
            Section {
                ForEach(mine) { list in
                    NavigationLink(value: StandardListRef(id: list.id)) {
                        StandardRowLabel(title: list.title, subtitle: "Yours · \(list.items.count) \(list.items.count == 1 ? "line" : "lines")",
                                         preview: searching ? Standards.preview(list.items.map(\.line), for: query) : [],
                                         isSafety: false)
                    }
                    .accessibilityIdentifier("standardList-\(list.title)")
                }
                ForEach(refs) { reference in
                    NavigationLink(value: ReferenceRef(id: reference.id)) {
                        StandardRowLabel(title: reference.title, subtitle: reference.summary,
                                         preview: searching ? Standards.preview(reference.entries.map(\.line), for: query) : [],
                                         isSafety: false)
                    }
                    .accessibilityIdentifier("reference-\(reference.id)")
                }
                ForEach(guides) { guide in
                    NavigationLink(value: GuideRef(id: guide.id)) {
                        StandardRowLabel(title: guide.title, subtitle: guide.summary,
                                         preview: searching ? Standards.preview(guide.steps, for: query, limit: 2) : [],
                                         isSafety: guide.isSafety)
                    }
                    .accessibilityIdentifier("guide-\(guide.id)")
                }
            } header: {
                Label(kind.title, systemImage: kind.systemImage)
            }
        }
    }

    /// Guides written in an earlier version become process lists, once.
    private func migrateOldGuides() {
        let old = JSONStorage.decode([CustomGuide].self, from: oldGuidesJSON) ?? []
        guard !old.isEmpty else { return }
        let merged = Standards.migrate(old, into: lists)
        let encoded = JSONStorage.encode(merged)
        guard !encoded.isEmpty else { return }
        listsJSON = encoded
        oldGuidesJSON = ""
    }
}

extension StandardItem {
    var line: String { value.isEmpty ? name : "\(name) · \(value)" }
}

extension ReferenceList.Entry {
    var line: String { "\(name) · \(value)" }
}

enum StandardListStorage {
    static func decode(_ json: String) -> [StandardList] { JSONStorage.decode([StandardList].self, from: json) ?? [] }
}

struct ReferenceRef: Hashable { let id: String }
struct StandardListRef: Hashable { let id: UUID }
/// Write a new list (nil) or edit one of yours.
struct StandardEditorRef: Hashable {
    let id: UUID?
    let kind: StandardList.Kind
}
struct GuideRef: Hashable { let id: String }

private struct StandardRowLabel: View {
    let title: String
    let subtitle: String
    let preview: [String]
    let isSafety: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            ForEach(preview, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(2)
            }
            if isSafety {
                Label("Safety", systemImage: "shield.lefthalf.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Built-in reference list

struct ReferenceDetailView: View {
    let reference: ReferenceList

    var body: some View {
        List {
            Section {
                Text(reference.summary).font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
                ForEach(reference.entries, id: \.self) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.subheadline).foregroundStyle(.secondary)
                        Text(entry.value).font(.headline)
                        if let detail = entry.detail {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .textSelection(.enabled)
                }
            }
            if !reference.sources.isEmpty {
                Section("Sources") {
                    ForEach(reference.sources, id: \.self) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) { Label(source.title, systemImage: "link") }
                        }
                    }
                }
            }
            Section {} footer: { Text(Standards.disclaimer) }
        }
        .navigationTitle(reference.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Your list

struct StandardListDetailView: View {
    let listID: UUID
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.standardLists, store: AppGroup.defaults) private var listsJSON = ""
    @State private var pendingStep: String?

    private var list: StandardList? { StandardListStorage.decode(listsJSON).first { $0.id == listID } }

    var body: some View {
        List {
            if let list {
                Section {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                        if list.kind.hasValues {
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.name)
                                Spacer(minLength: 12)
                                Text(item.value)
                                    .font(.body.weight(.semibold))
                                    .multilineTextAlignment(.trailing)
                            }
                            .textSelection(.enabled)
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 20)
                                Text(item.name).frame(maxWidth: .infinity, alignment: .leading)
                                Button { pendingStep = item.name } label: {
                                    Image(systemName: "plus.circle").imageScale(.large)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add step \(index + 1) as a task")
                            }
                        }
                    }
                } header: {
                    Label(list.kind.title, systemImage: list.kind.systemImage)
                } footer: {
                    if !list.kind.hasValues { Text("Tap + to add a step to your tasks. You'll confirm first.") }
                }
                if !list.note.isEmpty {
                    Section("Note") { Text(list.note) }
                }
            } else {
                Text("This list was deleted.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(list?.title ?? "List")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let list {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Edit", value: StandardEditorRef(id: list.id, kind: list.kind))
                }
            }
        }
        .confirmationDialog("Add this step as a task?",
                            isPresented: Binding(get: { pendingStep != nil }, set: { if !$0 { pendingStep = nil } }),
                            titleVisibility: .visible) {
            Button("Add task") {
                if let step = pendingStep, let list { StepTask.add(step, from: list.title, safety: false, in: context, router: router) }
                pendingStep = nil
            }
            Button("Cancel", role: .cancel) { pendingStep = nil }
        } message: {
            Text(pendingStep ?? "")
        }
    }
}

/// Write or edit one of your lists.
struct StandardListEditor: View {
    let existing: StandardList?
    let kind: StandardList.Kind
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.standardLists, store: AppGroup.defaults) private var listsJSON = ""
    @State private var draft = StandardList()
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField(titlePlaceholder, text: $draft.title)
                    .accessibilityIdentifier("standardTitle")
                Picker("Type", selection: $draft.kind) {
                    ForEach(StandardList.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                ForEach($draft.items) { $item in
                    let index = draft.items.firstIndex { $0.id == item.id } ?? 0
                    if draft.kind.hasValues {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField(draft.kind.namePlaceholder, text: $item.name)
                                .accessibilityIdentifier("standardItemName-\(index)")
                            TextField(draft.kind.valuePlaceholder, text: $item.value)
                                .font(.body.weight(.semibold))
                                .accessibilityIdentifier("standardItemValue-\(index)")
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)").foregroundStyle(.secondary).frame(width: 20)
                            TextField("Step", text: $item.name, axis: .vertical)
                                .accessibilityIdentifier("standardItemName-\(index)")
                        }
                    }
                }
                .onDelete { draft.items.remove(atOffsets: $0) }
                Button {
                    draft.items.append(StandardItem(name: ""))
                } label: {
                    Label(draft.kind.hasValues ? "Add line" : "Add step", systemImage: "plus")
                }
                .accessibilityIdentifier("standardAddLine")
                SensitiveContentNotice(text: draft.items.map(\.line).joined(separator: "\n"))
            } header: {
                Text(draft.kind.hasValues ? "Lines" : "Steps")
            } footer: {
                Text("Swipe a line to delete it.")
            }
            Section {
                TextField("Note, e.g. Posted on the cooler door (optional)", text: $draft.note, axis: .vertical)
            }
            if existing != nil {
                Section {
                    Button("Delete list", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(existing == nil ? "New \(kind.singular)" : "Edit list")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("standardSave")
            }
        }
        .confirmationDialog("Delete this list?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                listsJSON = JSONStorage.encode(StandardListStorage.decode(listsJSON).filter { $0.id != draft.id })
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let existing {
                draft = existing
            } else {
                draft = StandardList(kind: kind, items: [StandardItem(name: ""), StandardItem(name: "")])
            }
            loaded = true
        }
    }

    private var titlePlaceholder: String {
        switch draft.kind {
        case .temperatures: return "Title, e.g. Frozen and dairy temps"
        case .quality: return "Title, e.g. Produce quality"
        case .process: return "Title, e.g. Baler won't start"
        }
    }

    private func save() {
        var all = StandardListStorage.decode(listsJSON)
        let list = draft.cleaned
        if let index = all.firstIndex(where: { $0.id == list.id }) { all[index] = list } else { all.append(list) }
        listsJSON = JSONStorage.encode(all)
        dismiss()
    }
}

// MARK: - Store process (built-in step list)

/// One store process: steps (each can become a task after confirming), who to check with, the
/// person's own store steps, and public sources.
struct GuideDetailView: View {
    let guide: CoachGuide
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.askStoreSteps, store: AppGroup.defaults) private var storeStepsJSON = ""
    @State private var ownSteps = ""
    @State private var loaded = false
    @State private var pendingStep: String?

    var body: some View {
        List {
            Section {
                Text(guide.summary).font(.headline)
                if guide.isSafety {
                    Label(SafetyNotice.emergencyMessage, systemImage: "phone.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                }
            }
            Section {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 20)
                        Text(step)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Button { pendingStep = step } label: {
                            Image(systemName: "plus.circle").imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add step \(index + 1) as a task")
                    }
                }
            } header: {
                Text("Steps")
            } footer: {
                Text("Tap + to add a step to your tasks. You'll confirm first.")
            }
            if let check = guide.checkWith {
                Section("Check with") {
                    Label(check, systemImage: "person.badge.shield.checkmark")
                }
            }
            Section {
                TextField("The steps your store trained you on…", text: $ownSteps, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("guideStoreSteps")
                SensitiveContentNotice(text: ownSteps)
            } header: {
                Text("Your store's steps")
            } footer: {
                Text("Kept on your phone and shown with this process.")
            }
            if !guide.sources.isEmpty {
                Section("Sources") {
                    ForEach(guide.sources, id: \.self) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) { Label(source.title, systemImage: "link") }
                        }
                    }
                }
            }
            Section {} footer: { Text(CoachGuides.disclaimer) }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            ownSteps = AskStepsStorage.decode(storeStepsJSON)[guide.id] ?? ""
            loaded = true
        }
        .onChange(of: ownSteps) { _, text in
            guard loaded else { return }
            storeStepsJSON = AskStepsStorage.setting(guide.id, to: text, in: storeStepsJSON)
        }
        .confirmationDialog("Add this step as a task?",
                            isPresented: Binding(get: { pendingStep != nil }, set: { if !$0 { pendingStep = nil } }),
                            titleVisibility: .visible) {
            Button("Add task") {
                if let step = pendingStep {
                    StepTask.add(step, from: guide.title, safety: guide.isSafety, in: context, router: router)
                }
                pendingStep = nil
            }
            .accessibilityIdentifier("guideAddTaskConfirm")
            Button("Cancel", role: .cancel) { pendingStep = nil }
        } message: {
            Text(pendingStep ?? "")
        }
    }
}

/// Turns one step of a process into a task, after the person confirmed it.
enum StepTask {
    @MainActor
    static func add(_ step: String, from title: String, safety: Bool, in context: ModelContext, router: AppRouter) {
        var draft = CaptureDraft()
        draft.rawText = step
        draft.title = step
        draft.kind = .task
        draft.category = safety ? .safety : .general
        draft.details = "From Standards: \(title)"
        let classification = EisenhowerClassifier.classify(ClassificationInput(
            text: step, category: draft.category, kind: .task, priority: .normal,
            dueDate: nil, hasDueTime: false, now: Date(), calendar: .current))
        draft.quadrant = classification.quadrant
        draft.classificationReasons = classification.reasons
        draft.isSafetyLocked = classification.isSafetyLocked
        if CaptureSaver.save(draft, in: context) != nil {
            router.showToast("Added to Tasks")
        }
    }
}
