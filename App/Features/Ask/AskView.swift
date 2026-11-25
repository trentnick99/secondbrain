import SwiftUI
import SwiftData
import SecondBrainCore

/// Ask: "what do I do if…". Suggests vetted guides (and the person's own store guides) that match the
/// question, plus Reddit and web searches that open in the browser. It doesn't generate answers, so it
/// never makes up steps that don't fit the store. Works offline.
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @AppStorage(SettingsKey.askStoreSteps, store: AppGroup.defaults) private var storeStepsJSON = ""
    @AppStorage(SettingsKey.customGuides, store: AppGroup.defaults) private var customJSON = ""
    @State private var question: String
    @State private var asked: String
    @FocusState private var fieldFocused: Bool

    init(initialQuestion: String? = nil) {
        let q = (initialQuestion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _question = State(initialValue: q)
        _asked = State(initialValue: q)
    }

    private var role: UserRole? { RoleStorage.decode(roleJSON) }
    private var trimmed: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var customGuides: [CustomGuide] { CustomGuideStorage.decode(customJSON) }
    private var custom: [CoachGuide] { customGuides.filter(\.isValid).map(\.guide) }

    var body: some View {
        NavigationStack {
            List {
                questionSection
                if asked.isEmpty {
                    suggestions
                } else {
                    results
                }
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GuideRef.self) { ref in
                if let guide = CoachGuides.guide(id: ref.id, including: custom) { GuideDetailView(guide: guide) }
            }
            .navigationDestination(for: CustomGuideRef.self) { ref in
                CustomGuideEditor(existing: customGuides.first { $0.id == ref.id })
            }
            .navigationDestination(for: CoachGuide.Category.self) { CategoryGuidesView(category: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if asked.isEmpty { fieldFocused = true } }
        }
    }

    // MARK: Question

    private var questionSection: some View {
        Section {
            TextField("e.g. We're short-staffed tonight, what first?", text: $question, axis: .vertical)
                .lineLimit(2...5)
                .focused($fieldFocused)
                .accessibilityIdentifier("askQuestionField")
            HStack {
                Button {
                    fieldFocused = false
                    asked = trimmed
                } label: {
                    Label("Ask", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmed.isEmpty)
                .accessibilityIdentifier("askSubmitButton")
                if !asked.isEmpty {
                    Button("Clear") {
                        question = ""
                        asked = ""
                        fieldFocused = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            SensitiveContentNotice(text: question)
        } header: {
            Text("Ask anything about running your area")
        } footer: {
            Text("Ask suggests guides that match your question. They're general steps, so your store's procedures and your store manager come first. Works offline.")
        }
    }

    // MARK: Before asking

    @ViewBuilder
    private var suggestions: some View {
        Section {
            ForEach(CoachGuides.suggested(for: role)) { GuideRow(guide: $0) }
        } header: {
            Text(role.map { "Suggested for a \($0.title.lowercased())" } ?? "Suggested")
        }
        Section {
            ForEach(custom) { GuideRow(guide: $0) }
            NavigationLink(value: CustomGuideRef(id: nil)) {
                Label("Write a guide for your store", systemImage: "square.and.pencil")
            }
            .accessibilityIdentifier("askNewGuide")
        } header: {
            Text("Your guides")
        } footer: {
            Text("Write the steps your store trained you on. Ask shows them first when they match.")
        }
        Section("Browse by topic") {
            ForEach(CoachGuide.Category.allCases, id: \.self) { category in
                NavigationLink(value: category) {
                    HStack {
                        Label(category.title, systemImage: category.systemImage)
                        Spacer()
                        Text("\(CoachGuides.all.filter { $0.category == category }.count)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        Section {} footer: { Text(CoachGuides.disclaimer) }
    }

    // MARK: After asking

    @ViewBuilder
    private var results: some View {
        if let notice = AskAssistant.emergency(in: asked) {
            Section {
                Label(notice.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("askEmergencyNotice")
            }
        }
        let guides = CoachGuides.search(asked, including: custom)
        Section {
            if guides.isEmpty {
                Text("No guide matches that yet. Try other words, or search online below.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(guides) { GuideRow(guide: $0) }
            }
        } header: {
            Text("Suggested guides")
        }
        Section {
            if let url = AskAssistant.redditSearchURL(asked) {
                Link(destination: url) {
                    Label("Search Reddit (r/walmart)", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityIdentifier("askRedditLink")
            }
            if let url = AskAssistant.webSearchURL(asked) {
                Link(destination: url) { Label("Search the web", systemImage: "safari") }
            }
        } header: {
            Text("Search online")
        } footer: {
            Text(AskAssistant.redditNote + " These open in your browser.")
        }
        Section {} footer: { Text(CoachGuides.disclaimer) }
    }
}

/// Navigation value for writing (nil) or editing one of your own guides.
struct CustomGuideRef: Hashable {
    let id: UUID?
}

enum CustomGuideStorage {
    static func decode(_ json: String) -> [CustomGuide] { JSONStorage.decode([CustomGuide].self, from: json) ?? [] }
}

/// Write or edit a guide for your store.
struct CustomGuideEditor: View {
    let existing: CustomGuide?
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.customGuides, store: AppGroup.defaults) private var customJSON = ""
    @State private var draft = CustomGuide()
    @State private var stepsText = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section {
                TextField("What situation? e.g. Baler won't start", text: $draft.title)
                    .accessibilityIdentifier("customGuideTitle")
                Picker("Topic", selection: $draft.category) {
                    ForEach(CoachGuide.Category.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section {
                TextField("One step per line", text: $stepsText, axis: .vertical)
                    .lineLimit(4...12)
                    .accessibilityIdentifier("customGuideSteps")
                SensitiveContentNotice(text: stepsText)
            } header: {
                Text("Steps")
            } footer: {
                Text("The steps your store trained you on. Don't include passwords, codes or anyone's personal details.")
            }
            Section {
                TextField("Who to check with (optional)", text: $draft.checkWith)
                TextField("Other words people might use (optional, commas)", text: $draft.extraKeywords)
            }
            if existing != nil {
                Section {
                    Button("Delete guide", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(existing == nil ? "New guide" : "Edit guide")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!current.isValid)
            }
        }
        .confirmationDialog("Delete this guide?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                customJSON = JSONStorage.encode(CustomGuideStorage.decode(customJSON).filter { $0.id != draft.id })
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            if let existing {
                draft = existing
                stepsText = existing.steps.joined(separator: "\n")
            }
            loaded = true
        }
    }

    private var current: CustomGuide {
        var guide = draft
        guide.steps = stepsText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^(\d{1,2}[.)]|[-•*])\s*"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
        return guide
    }

    private func save() {
        var all = CustomGuideStorage.decode(customJSON)
        if let index = all.firstIndex(where: { $0.id == draft.id }) { all[index] = current } else { all.append(current) }
        customJSON = JSONStorage.encode(all)
        dismiss()
    }
}

/// Navigation value for a guide.
struct GuideRef: Hashable {
    let id: String
}

struct GuideRow: View {
    let guide: CoachGuide

    var body: some View {
        NavigationLink(value: GuideRef(id: guide.id)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(guide.title).font(.headline)
                Text(guide.summary).font(.subheadline).foregroundStyle(.secondary)
                if guide.isSafety {
                    Label("Safety", systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("guide-\(guide.id)")
    }
}

private struct CategoryGuidesView: View {
    let category: CoachGuide.Category

    var body: some View {
        List {
            ForEach(CoachGuides.all.filter { $0.category == category }) { GuideRow(guide: $0) }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One guide: steps (each can become a task after confirming), who to check with, the person's own store
/// steps, and public sources.
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
                    Label(AskAssistant.emergencyMessage, systemImage: "phone.fill")
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
            if !guide.isCustom {
            Section {
                TextField("The steps your store trained you on…", text: $ownSteps, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("guideStoreSteps")
                SensitiveContentNotice(text: ownSteps)
            } header: {
                Text("Your store's steps")
            } footer: {
                Text("Kept on your phone and shown with this guide.")
            }
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
            Section {
                if let url = AskAssistant.redditSearchURL(guide.title) {
                    Link(destination: url) { Label("What others say on Reddit", systemImage: "bubble.left.and.bubble.right") }
                }
            } footer: {
                Text(CoachGuides.disclaimer)
            }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if guide.isCustom, let id = UUID(uuidString: String(guide.id.dropFirst(CustomGuide.idPrefix.count))) {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink("Edit", value: CustomGuideRef(id: id))
                }
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
                if let step = pendingStep { addTask(step) }
                pendingStep = nil
            }
            .accessibilityIdentifier("guideAddTaskConfirm")
            Button("Cancel", role: .cancel) { pendingStep = nil }
        } message: {
            Text(pendingStep ?? "")
        }
    }

    private func addTask(_ step: String) {
        var draft = CaptureDraft()
        draft.rawText = step
        draft.title = step
        draft.kind = .task
        draft.category = guide.isSafety ? .safety : (guide.category == .people ? .people : .general)
        draft.details = "From Ask: \(guide.title)"
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
