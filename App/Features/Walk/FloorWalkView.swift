import SwiftUI
import SwiftData
import SecondBrainCore

/// A guided walk of your areas: safety first, then shelves and standards. Mark each check OK or
/// Needs work; at the end, the misses you choose become tasks. Progress is kept if you leave.
struct FloorWalkView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @AppStorage(SettingsKey.floorWalkState, store: AppGroup.defaults) private var stateJSON = ""
    @State private var state = FloorWalkState()
    @State private var loaded = false
    @State private var confirmRestart = false

    private var sections: [WalkSection] { FloorWalkChecklist.sections(for: RoleStorage.decode(roleJSON)) }

    var body: some View {
        let sections = sections
        let total = FloorWalkChecklist.checkCount(sections)
        let marked = FloorWalkChecklist.markedCount(state, sections)
        let findings = FloorWalkChecklist.findings(state, sections)

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(marked) of \(total) checked").font(.headline)
                            Spacer()
                            if !findings.isEmpty {
                                Text("\(findings.count) need work")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                        ProgressView(value: Double(marked), total: Double(max(total, 1)))
                            .tint(Theme.accent)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Tap ✓ if it's fine or ! if it needs work. Add a note to say exactly what. Nothing becomes a task until you finish and choose.")
                }

                ForEach(sections) { section in
                    Section {
                        ForEach(section.checks) { check in
                            WalkCheckRow(check: check, area: section.area, state: $state)
                        }
                    } header: {
                        Text(section.area)
                    }
                }

                Section {
                    NavigationLink(value: WalkReviewRef()) {
                        Label(findings.isEmpty ? "Finish walk" : "Finish walk · \(findings.count) to add as tasks",
                              systemImage: "flag.checkered")
                            .font(.headline)
                    }
                    .disabled(marked == 0)
                    .accessibilityIdentifier("walkFinishButton")
                }
            }
            .navigationTitle("Floor walk")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WalkReviewRef.self) { _ in
                WalkReviewView(state: state, sections: sections) {
                    stateJSON = ""
                    state = FloorWalkState()
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Start over") { confirmRestart = true }.disabled(marked == 0)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Start the walk over?", isPresented: $confirmRestart, titleVisibility: .visible) {
                Button("Start over", role: .destructive) {
                    state = FloorWalkState()
                    stateJSON = ""
                }
            } message: {
                Text("This clears the checks and notes for this walk. No tasks are changed.")
            }
            .onAppear(perform: load)
            .onChange(of: state) { _, new in
                guard loaded else { return }
                stateJSON = (try? JSONEncoder().encode(new)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        if let data = stateJSON.data(using: .utf8), let saved = try? JSONDecoder().decode(FloorWalkState.self, from: data) {
            // A walk left from an earlier day starts fresh.
            if Calendar.current.isDateInToday(saved.startedAt) { state = saved }
        }
        loaded = true
    }
}

private struct WalkReviewRef: Hashable {}

private struct WalkCheckRow: View {
    let check: WalkCheck
    let area: String
    @Binding var state: FloorWalkState

    var body: some View {
        let mark = state.mark(area, check)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if check.isSafety {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(Theme.danger)
                        .accessibilityLabel("Safety")
                }
                Text(check.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                markButton(.ok, systemImage: "checkmark", tint: Theme.success, current: mark, label: "OK")
                markButton(.needsWork, systemImage: "exclamationmark", tint: Theme.warning, current: mark, label: "Needs work")
            }
            if mark == .needsWork {
                TextField("What needs doing? (optional)", text: Binding(
                    get: { state.notes[FloorWalkState.key(area, check)] ?? "" },
                    set: { state.notes[FloorWalkState.key(area, check)] = $0 }), axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...3)
                    .padding(.leading, check.isSafety ? 28 : 0)
            }
        }
        .padding(.vertical, 2)
    }

    private func markButton(_ value: FloorWalkState.Mark, systemImage: String, tint: Color,
                            current: FloorWalkState.Mark?, label: String) -> some View {
        let isOn = current == value
        return Button {
            withAnimation(.snappy) { state.set(isOn ? nil : value, area, check) }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .frame(width: 34, height: 34)
                .background(isOn ? tint : Theme.surfaceRaised, in: Circle())
                .foregroundStyle(isOn ? Color.white : tint)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(label): \(check.title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The misses from a walk: choose which become tasks, and optionally keep a summary note.
private struct WalkReviewView: View {
    let state: FloorWalkState
    let sections: [WalkSection]
    let onFinish: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @State private var chosen: Set<String>
    @State private var saveSummary = true

    init(state: FloorWalkState, sections: [WalkSection], onFinish: @escaping () -> Void) {
        self.state = state
        self.sections = sections
        self.onFinish = onFinish
        _chosen = State(initialValue: Set(FloorWalkChecklist.findings(state, sections).map(\.id)))
    }

    var body: some View {
        let findings = FloorWalkChecklist.findings(state, sections)
        List {
            if findings.isEmpty {
                Section {
                    Label("Everything you checked looked good.", systemImage: "hand.thumbsup.fill")
                        .foregroundStyle(Theme.success)
                }
            } else {
                Section {
                    ForEach(findings) { finding in
                        Button {
                            if chosen.contains(finding.id) { chosen.remove(finding.id) } else { chosen.insert(finding.id) }
                        } label: {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: chosen.contains(finding.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(chosen.contains(finding.id) ? Theme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(finding.title).foregroundStyle(.primary)
                                    if finding.check.isSafety {
                                        Text("Safety").font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Needs work")
                } footer: {
                    Text("Ticked items become tasks. Safety items go to Do First. Dates aren't added; set one in Tasks if you need it.")
                }
            }
            Section {
                Toggle("Save a walk summary to Notes", isOn: $saveSummary)
                Button {
                    finish(findings)
                } label: {
                    Text(chosen.isEmpty ? "Finish walk" : "Add \(chosen.count) task\(chosen.count == 1 ? "" : "s") and finish")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("walkAddTasksButton")
            }
        }
        .navigationTitle("Finish walk")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func finish(_ findings: [WalkFinding]) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        var added = 0
        for finding in findings where chosen.contains(finding.id) {
            var draft = CaptureDraft()
            draft.rawText = finding.title
            draft.title = finding.title
            draft.kind = .task
            draft.category = finding.check.isSafety ? .safety : .operations
            draft.department = finding.fileUnderArea ? finding.area : ""
            draft.details = "From floor walk (\(stamp)): \(finding.check.title)"
            let classification = EisenhowerClassifier.classify(ClassificationInput(
                text: finding.title + " " + finding.check.title, category: draft.category, kind: .task, priority: .normal,
                dueDate: nil, hasDueTime: false, now: Date(), calendar: .current))
            draft.quadrant = classification.quadrant
            draft.classificationReasons = classification.reasons
            draft.isSafetyLocked = classification.isSafetyLocked
            if CaptureSaver.save(draft, in: context) != nil { added += 1 }
        }
        if saveSummary {
            let note = Note(title: "Floor walk · \(stamp)", body: FloorWalkChecklist.summary(state, sections), type: .operational)
            note.tagsRaw = "floor walk"
            context.insert(note)
            TaskActions.save(context)
        }
        router.showToast(added == 0 ? "Walk saved" : "Added \(added) task\(added == 1 ? "" : "s")")
        onFinish()
    }
}
