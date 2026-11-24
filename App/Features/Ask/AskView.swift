import SwiftUI
import SwiftData
import SecondBrainCore

/// Ask: management questions, suggestions and "what do I do if…".
/// Offline guides always work; Apple's on-device model writes an answer when available;
/// Reddit and web searches open in the browser. Nothing is saved unless the person taps to save it.
struct AskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @AppStorage(SettingsKey.askUsesAI, store: AppGroup.defaults) private var usesAI = true
    @AppStorage(SettingsKey.askStoreSteps, store: AppGroup.defaults) private var storeStepsJSON = ""
    @State private var question: String
    @State private var asked: String
    @State private var answer: String?
    @State private var answerError: String?
    @State private var isThinking = false
    @FocusState private var fieldFocused: Bool

    init(initialQuestion: String? = nil) {
        let q = (initialQuestion ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _question = State(initialValue: q)
        _asked = State(initialValue: q)
    }

    private var role: UserRole? { RoleStorage.decode(roleJSON) }
    private var trimmed: String { question.trimmingCharacters(in: .whitespacesAndNewlines) }

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
                if let guide = CoachGuides.guide(id: ref.id) { GuideDetailView(guide: guide) }
            }
            .navigationDestination(for: CoachGuide.Category.self) { CategoryGuidesView(category: $0) }
            .navigationDestination(for: AnswerStepsRef.self) { AnswerStepsView(ref: $0) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: asked) { await writeAnswer() }
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
            Text("Guides work offline. Written answers come from Apple Intelligence on your iPhone, so your question stays on your phone.")
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
        if usesAI { answerSection }
        let guides = CoachGuides.search(asked)
        Section {
            if guides.isEmpty {
                Text("No guide matches that yet. Try other words, or search online below.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(guides) { GuideRow(guide: $0) }
            }
        } header: {
            Text("Guides")
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

    @ViewBuilder
    private var answerSection: some View {
        let availability = OnDeviceAssistant.availability
        if availability == .ready {
            Section {
                if isThinking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Writing an answer on your iPhone…").foregroundStyle(.secondary)
                    }
                } else if let answer {
                    Text(answer)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("askAnswer")
                    let steps = AskAssistant.steps(fromAnswer: answer)
                    if !steps.isEmpty {
                        NavigationLink(value: AnswerStepsRef(question: asked, steps: steps)) {
                            Label("Add steps as tasks", systemImage: "checklist")
                        }
                    }
                    Button { saveAnswer(answer) } label: { Label("Save as note", systemImage: "square.and.arrow.down") }
                } else if let answerError {
                    Text(answerError).foregroundStyle(.secondary)
                }
            } header: {
                Label("Answer", systemImage: "sparkles")
            } footer: {
                Text("Written by Apple Intelligence on your iPhone. It can be wrong. Your store's procedures and your store manager come first.")
            }
        } else {
            Section {
                Label(availability.message, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("askAIStatus")
            }
        }
    }

    private func writeAnswer() async {
        answer = nil
        answerError = nil
        guard !asked.isEmpty, usesAI, OnDeviceAssistant.availability == .ready else { return }
        isThinking = true
        defer { isThinking = false }
        do {
            let text = try await OnDeviceAssistant.answer(
                question: asked, guides: CoachGuides.search(asked, limit: 3), role: role,
                storeSteps: AskStepsStorage.decode(storeStepsJSON))
            guard !Task.isCancelled else { return }
            answer = text.isEmpty ? nil : text
            if text.isEmpty { answerError = "No answer this time. The guides below still apply." }
        } catch is CancellationError {
        } catch {
            answerError = "Apple Intelligence couldn't answer that one. Try rewording it, or use the guides below."
        }
    }

    private func saveAnswer(_ text: String) {
        let title = "Ask: " + (asked.count > 50 ? String(asked.prefix(47)) + "…" : asked)
        let note = Note(title: title, body: "Q: \(asked)\n\n\(text)\n\n(Written by Apple Intelligence on this iPhone. Check store policy.)", type: .general)
        note.tagsRaw = "ask"
        context.insert(note)
        try? context.save()
        router.showToast("Saved to Notes")
    }
}

/// The steps of a written answer, offered as tasks.
struct AnswerStepsRef: Hashable {
    let question: String
    let steps: [String]
}

/// Pick which steps of a written answer become tasks. Nothing is added until you tap Add.
private struct AnswerStepsView: View {
    let ref: AnswerStepsRef
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var chosen: Set<Int>

    init(ref: AnswerStepsRef) {
        self.ref = ref
        _chosen = State(initialValue: Set(ref.steps.indices))
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(ref.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: chosen.contains(index) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen.contains(index) ? Theme.accent : .secondary)
                            Text(step).foregroundStyle(.primary)
                        }
                    }
                }
            } footer: {
                Text("Tick the steps you want as tasks. You can edit them in Tasks afterward.")
            }
        }
        .navigationTitle("Add as tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add \(chosen.count)") { add() }.disabled(chosen.isEmpty)
            }
        }
    }

    private func add() {
        for index in chosen.sorted() {
            let step = ref.steps[index]
            var draft = CaptureDraft()
            draft.rawText = step
            draft.title = step
            draft.kind = .task
            draft.details = "From Ask: \(ref.question)"
            let classification = EisenhowerClassifier.classify(ClassificationInput(
                text: step, category: .general, kind: .task, priority: .normal,
                dueDate: nil, hasDueTime: false, now: Date(), calendar: .current))
            draft.quadrant = classification.quadrant
            draft.classificationReasons = classification.reasons
            draft.isSafetyLocked = classification.isSafetyLocked
            if classification.isSafetyLocked { draft.category = .safety }
            _ = CaptureSaver.save(draft, in: context)
        }
        router.showToast(chosen.count == 1 ? "Added 1 task" : "Added \(chosen.count) tasks")
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
            Section {
                TextField("The steps your store trained you on…", text: $ownSteps, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("guideStoreSteps")
                SensitiveContentNotice(text: ownSteps)
            } header: {
                Text("Your store's steps")
            } footer: {
                Text("Kept on your phone. Ask uses them when it writes answers.")
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
