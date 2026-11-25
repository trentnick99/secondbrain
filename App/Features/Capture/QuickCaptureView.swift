import SwiftData
import SwiftUI
import SecondBrainCore

/// Quick Capture — type or speak, glance at the interpretation, save. Clear captures save with the
/// Return key; anything ambiguous is shown for confirmation first. "Inbox" saves the raw text as-is.
struct QuickCaptureView: View {
    var initialKind: CaptureKind?
    /// Pre-filled text, e.g. from a Shortcuts link. It's only interpreted — saving still takes a tap.
    var initialText: String? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var associates: [Associate]

    @State private var text = ""
    @State private var draft = CaptureDraft()
    @State private var speech = SpeechCaptureService()
    @State private var textBeforeDictation = ""
    @State private var showAdjust = false
    @State private var saveTrigger = 0
    @FocusState private var focused: Bool

    private let parser = NaturalLanguageParser()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputField
                    SensitiveContentNotice(text: text)
                    kindChips
                    if !draft.isEmpty {
                        InterpretationCard(draft: draft, onAdjust: { showAdjust = true })
                        if draft.needsReview { ambiguityList }
                    } else {
                        examples
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Quick Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.reset(); dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $showAdjust) {
                CaptureAdjustSheet(draft: $draft, associates: associates)
            }
        }
        .onAppear {
            focused = true
            if let initialText, text.isEmpty {
                text = initialText.replacingOccurrences(of: "\n", with: " ")
            }
            if let initialKind {
                draft.kind = initialKind
                draft.locked.insert(.kind)
            }
        }
        .onChange(of: text) { _, newValue in
            // Multi-line fields insert a newline on Return; in Quick Capture, Return means "save".
            if newValue.contains("\n") {
                text = newValue.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                reparse()
                handleReturn()
                return
            }
            reparse()
        }
        .onChange(of: speech.transcript) { _, newValue in
            guard !newValue.isEmpty else { return }
            text = textBeforeDictation.isEmpty ? newValue : textBeforeDictation + " " + newValue
        }
        .onDisappear { speech.reset() }
        .sensoryFeedback(.success, trigger: saveTrigger)
    }

    // MARK: Input

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("What do you need to remember?", text: $text, axis: .vertical)
                .font(.title3)
                .lineLimit(2...6)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(handleReturn)
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(speech.isListening ? Theme.accent : Theme.stroke, lineWidth: speech.isListening ? 2 : 1))
                .accessibilityIdentifier("captureTextField")
            if speech.isListening {
                Label(speech.isOnDevice ? "Listening (on-device)…" : "Listening…", systemImage: "waveform")
                    .font(.footnote).foregroundStyle(Theme.accent)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else if case .unavailable(let message) = speech.state {
                Label(message, systemImage: "mic.slash").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CaptureKind.allCases) { kind in
                    Chip(title: kind.title, systemImage: kind.systemImage, isSelected: draft.kind == kind) {
                        draft.kind = kind
                        draft.locked.insert(.kind)
                    }
                    .accessibilityIdentifier("captureKind-\(kind.rawValue)")
                }
            }
            .padding(.trailing, 24)
        }
        .trailingFade()
    }

    private var ambiguityList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Check before saving", systemImage: "exclamationmark.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.warning)
            ForEach(draft.ambiguities) { item in
                Text("• " + item.message).font(.subheadline)
            }
            Button("Adjust details") { showAdjust = true }
                .font(.subheadline.weight(.semibold))
        }
        .card()
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title: "Try saying", systemImage: "sparkles")
            ForEach(["Check with John tomorrow about his schedule.",
                     "Make sure dairy is cleaned up before Friday.",
                     "Remind me every Monday to review safety observations.",
                     "Talk to the overnight coach about the freight backlog."], id: \.self) { sample in
                Button { text = sample } label: {
                    Text("“\(sample)”").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                if !speech.isListening { textBeforeDictation = text }
                Task { await speech.toggle() }
            } label: {
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.title3)
                    .frame(width: 52, height: 52)
                    .background(speech.isListening ? Theme.danger : Theme.surfaceRaised, in: Circle())
                    .foregroundStyle(speech.isListening ? Color.white : Color.primary)
            }
            .accessibilityLabel(speech.isListening ? "Stop voice capture" : "Start voice capture")

            Button {
                saveToInbox()
            } label: {
                Label("Inbox", systemImage: "tray.and.arrow.down")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.bordered)
            .disabled(draft.isEmpty)
            .accessibilityHint("Saves exactly what you typed to sort later")

            Button {
                save()
            } label: {
                Text(draft.needsReview ? "Confirm & Save" : "Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft.isEmpty)
            .accessibilityIdentifier("captureSaveButton")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Actions

    private func reparse() {
        let captureContext = AppSettings.captureContext(knownAssociates: associates.filter { !$0.isArchived }.map(\.name))
        let parsed = parser.parse(text, context: captureContext)
        draft = draft.merging(parsed)
    }

    private func handleReturn() {
        if draft.needsReview {
            focused = false   // reveal the interpretation; the person confirms with the button
        } else {
            save()
        }
    }

    private func save() {
        guard !draft.isEmpty else { return }
        speech.reset()
        if let result = CaptureSaver.save(draft, in: context) {
            saveTrigger += 1
            router.showToast(result.confirmation)
        }
        dismiss()
    }

    private func saveToInbox() {
        speech.reset()
        if CaptureSaver.saveToInbox(text, in: context) != nil {
            saveTrigger += 1
            router.showToast("Saved to Inbox")
        }
        dismiss()
    }
}

/// Shows how the capture was understood.
struct InterpretationCard: View {
    /// "Jordan", "Priya (new)" for someone not in Associates yet, or "Stock 2 (team)" — teams never become contacts.
    private var personLabel: String {
        if StoreRole.isGroupName(draft.associateName) { return "\(draft.associateName) (team)" }
        return draft.associateIsKnown ? draft.associateName : "\(draft.associateName) (new)"
    }

    let draft: CaptureDraft
    var onAdjust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Interpreted as", systemImage: "wand.and.stars")
                Button("Adjust", action: onAdjust).font(.subheadline.weight(.semibold))
            }
            Text(draft.title.isEmpty ? draft.rawText : draft.title)
                .font(.headline)
            if !draft.details.isEmpty {
                Text(draft.details).font(.subheadline).foregroundStyle(.secondary)
            }
            FlowLayout(spacing: 6) {
                tag(draft.kind.title, draft.kind.systemImage)
                if !draft.associateName.isEmpty {
                    tag(personLabel, StoreRole.isGroupName(draft.associateName) ? "person.3" : "person")
                }
                if !draft.delegateTo.isEmpty { tag("Hand off to \(draft.delegateTo) · waiting", "person.badge.clock") }
                if !draft.department.isEmpty { tag(draft.department, "building.2") }
                if let rule = draft.recurrence {
                    tag(rule.summary(calendar: .current), "repeat")
                }
                if let due = draft.dueDate {
                    tag(RelativeDateText.dueText(due: due, hasTime: draft.hasDueTime, now: Date(), calendar: .current), "calendar")
                }
                if let reminder = draft.reminderDate {
                    tag("Remind " + RelativeDateText.dueText(due: reminder, hasTime: true, now: Date(), calendar: .current)
                        + (draft.reminderIsDefault ? " (default)" : ""), "bell")
                }
                if draft.createsNote == false {
                    tag(draft.category.title, draft.category.systemImage)
                    if draft.priority != .normal { tag(draft.priority.title, "flag") }
                }
            }
            if draft.createsNote == false {
                HStack(alignment: .top, spacing: 8) {
                    QuadrantBadge(quadrant: draft.quadrant)
                    if let reason = draft.classificationReasons.first {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(draft.notes, id: \.self) { note in
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    private func tag(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.surfaceRaised, in: Capsule())
    }
}
