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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: Standards.shareText(reference)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share this list")
            }
        }
    }
}

// MARK: - Your list

struct StandardListDetailView: View {
    let listID: UUID
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.standardLists, store: AppGroup.defaults) private var listsJSON = ""
    @State private var pendingStep: String?
    @State private var checking: StandardItem?
    @Query private var checks: [StandardCheck]

    init(listID: UUID) {
        self.listID = listID
        _checks = Query(filter: #Predicate<StandardCheck> { $0.listID == listID }, sort: \.checkedAt, order: .reverse)
    }

    /// Checks from today, newest first.
    private var todaysChecks: [StandardCheck] {
        let start = Calendar.current.startOfDay(for: Date())
        return checks.filter { $0.checkedAt >= start }
    }

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
                                Button { checking = item } label: {
                                    Image(systemName: list.kind == .temperatures ? "thermometer.medium" : "checkmark.circle")
                                        .imageScale(.large)
                                        .frame(minWidth: 36)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Check \(item.name)")
                                .accessibilityIdentifier("check-\(item.name)")
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
                if list.kind.hasValues {
                    Section {
                        if todaysChecks.isEmpty {
                            Text(list.kind == .temperatures ? "No readings yet today. Tap the thermometer to record one."
                                                            : "No checks yet today. Tap the check mark to record one.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(todaysChecks) { check in CheckRow(check: check) }
                    } header: {
                        Text("Today's checks")
                    } footer: {
                        if checks.count > todaysChecks.count {
                            Text("\(checks.count - todaysChecks.count) earlier check\(checks.count - todaysChecks.count == 1 ? "" : "s") are kept and included in backups.")
                        }
                    }
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
        .sheet(item: $checking) { item in
            if let list { StandardCheckSheet(list: list, item: item) }
        }
        .toolbar {
            if let list {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Edit", value: StandardEditorRef(id: list.id, kind: list.kind))
                }
                ToolbarItem(placement: .secondaryAction) {
                    ShareLink(item: Standards.shareText(list)) { Label("Share", systemImage: "square.and.arrow.up") }
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: Standards.shareText(guide)) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share these steps")
            }
        }
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

// MARK: - Check-offs

private struct CheckRow: View {
    let check: StandardCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: check.isWithinStandard ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(check.isWithinStandard ? Theme.success : Theme.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.reading.isEmpty ? check.itemName : "\(check.itemName) · \(check.reading)")
                    .font(.subheadline.weight(.semibold))
                Text(check.isWithinStandard ? "Within \(check.standard)" : "Outside \(check.standard)")
                    .font(.caption)
                    .foregroundStyle(check.isWithinStandard ? Color.secondary : Theme.danger)
                if !check.note.isEmpty {
                    Text(check.note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(check.checkedAt.formatted(date: .omitted, time: .shortened))
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Record one reading or check against a line of your list. For temperatures, Coach Spark reads the
/// limit from the standard's words when it can ("-10°F or colder"); otherwise you say whether it meets
/// the standard. A reading outside the standard can become a task, after you confirm.
struct StandardCheckSheet: View {
    let list: StandardList
    let item: StandardItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var readingText = ""
    @State private var meets: Bool?
    @State private var note = ""
    @State private var offerTask = false
    @State private var saved = 0
    @FocusState private var focused: Bool

    private var isTemperature: Bool { list.kind == .temperatures }
    private var rule: TemperatureRule? { isTemperature ? TemperatureRule.parse(item.value) : nil }
    private var reading: Double? { TemperatureRule.reading(from: readingText) }
    /// Known from the reading and the rule, when both are clear.
    private var computed: Bool? {
        guard let rule, let reading else { return nil }
        return rule.allows(reading)
    }
    private var within: Bool? { computed ?? meets }
    private var canSave: Bool { within != nil && (!isTemperature || reading != nil) }

    private var readingLabel: String {
        guard let reading else { return "" }
        let number = reading.rounded() == reading ? String(Int(reading)) : String(reading)
        return number + "°F"
    }

    private var taskTitle: String {
        isTemperature
            ? "Fix \(item.name): \(readingLabel), standard \(item.value)"
            : "Fix \(item.name): doesn't meet \(item.value.isEmpty ? "the standard" : item.value)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Standard", value: item.value.isEmpty ? "Not written down" : item.value)
                } header: {
                    Text(item.name)
                }
                if isTemperature {
                    Section {
                        TextField("Temperature you read, e.g. -12", text: $readingText)
                            .keyboardType(.numbersAndPunctuation)
                            .focused($focused)
                            .accessibilityIdentifier("checkReading")
                        if let computed {
                            Label(computed ? "Within the standard" : "Outside the standard",
                                  systemImage: computed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(computed ? Theme.success : Theme.danger)
                                .accessibilityIdentifier("checkStatus")
                        }
                    } header: {
                        Text("Reading (°F)")
                    }
                }
                if computed == nil {
                    Section {
                        Picker("Meets the standard?", selection: $meets) {
                            Text("Yes").tag(Optional(true))
                            Text("No").tag(Optional(false))
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Meets the standard?")
                    } footer: {
                        if isTemperature && rule == nil {
                            Text("Coach Spark couldn't read a limit from \"\(item.value)\", so you decide.")
                        }
                    }
                }
                Section {
                    TextField("Note (optional), e.g. door was left open", text: $note, axis: .vertical)
                }
            }
            .navigationTitle(isTemperature ? "Record a reading" : "Record a check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("checkSave")
                }
            }
            .confirmationDialog("Outside the standard. Add a task to fix it?", isPresented: $offerTask, titleVisibility: .visible) {
                Button("Add task") {
                    addTask()
                    dismiss()
                }
                Button("Not now", role: .cancel) { dismiss() }
            } message: {
                Text(taskTitle)
            }
            .sensoryFeedback(.success, trigger: saved)
            .onAppear { focused = isTemperature }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let within else { return }
        let check = StandardCheck(listID: list.id, itemID: item.id, listTitle: list.title, itemName: item.name,
                                  standard: item.value, reading: isTemperature ? readingLabel : "",
                                  isWithinStandard: within, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        context.insert(check)
        TaskActions.save(context)
        saved += 1
        if within {
            router.showToast("Check saved")
            dismiss()
        } else {
            offerTask = true
        }
    }

    private func addTask() {
        StepTask.add(taskTitle, from: list.title, safety: isTemperature, in: context, router: router)
    }
}
