import SwiftUI
import SecondBrainCore

/// Lets the person correct any part of the interpretation before saving. Edited fields are locked
/// so continued typing in the capture field doesn't overwrite them.
struct CaptureAdjustSheet: View {
    @Binding var draft: CaptureDraft
    let associates: [Associate]
    @Environment(\.dismiss) private var dismiss
    @State private var newPersonName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    Picker("Type", selection: bind(\.kind, .kind)) {
                        ForEach(CaptureKind.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    TextField("Title", text: bind(\.title, .title), axis: .vertical)
                    TextField("Details (optional)", text: bind(\.details, .title), axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Who") {
                    Picker("Associate", selection: bind(\.associateName, .associate)) {
                        Text("None").tag("")
                        ForEach(associates.filter { !$0.isArchived }) { person in
                            Text(person.name).tag(person.name)
                        }
                        if !draft.associateName.isEmpty && !associates.contains(where: { $0.name.caseInsensitiveCompare(draft.associateName) == .orderedSame }) {
                            Text("\(draft.associateName) (new)").tag(draft.associateName)
                        }
                    }
                    HStack {
                        TextField("Or add a new person", text: $newPersonName)
                            .textInputAutocapitalization(.words)
                        Button("Use") {
                            let name = newPersonName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty else { return }
                            draft.associateName = name
                            draft.associateIsKnown = false
                            draft.locked.insert(.associate)
                            newPersonName = ""
                        }
                        .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Picker("Department", selection: bind(\.department, .department)) {
                        Text("None").tag("")
                        ForEach(DepartmentLexicon.allNames, id: \.self) { Text($0).tag($0) }
                        if !draft.department.isEmpty && !DepartmentLexicon.allNames.contains(draft.department) {
                            Text(draft.department).tag(draft.department)
                        }
                    }
                }

                if !draft.createsNote {
                    Section("When") {
                        Toggle("Due date", isOn: Binding(
                            get: { draft.dueDate != nil },
                            set: { on in
                                draft.dueDate = on ? (draft.dueDate ?? Calendar.current.startOfDay(for: Date())) : nil
                                if !on { draft.hasDueTime = false }
                                draft.locked.insert(.due)
                            }))
                        if draft.dueDate != nil {
                            Toggle("Specific time", isOn: bind(\.hasDueTime, .due))
                            DatePicker("Due", selection: Binding(
                                get: { draft.dueDate ?? Date() },
                                set: { draft.dueDate = $0; draft.locked.insert(.due) }),
                                       displayedComponents: draft.hasDueTime ? [.date, .hourAndMinute] : [.date])
                        }
                        Toggle("Reminder", isOn: Binding(
                            get: { draft.reminderDate != nil },
                            set: { on in
                                draft.reminderDate = on ? (draft.reminderDate ?? defaultReminder) : nil
                                draft.reminderIsDefault = false
                                draft.locked.insert(.reminder)
                            }))
                        if draft.reminderDate != nil {
                            DatePicker("Remind at", selection: Binding(
                                get: { draft.reminderDate ?? Date() },
                                set: { draft.reminderDate = $0; draft.reminderIsDefault = false; draft.locked.insert(.reminder) }),
                                       in: Date()..., displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    Section("Repeat") {
                        RecurrenceEditor(rule: Binding(
                            get: { draft.recurrence },
                            set: { draft.recurrence = $0; draft.locked.insert(.recurrence) }))
                    }

                    Section {
                        QuadrantPicker(quadrant: bind(\.quadrant, .quadrant))
                        if draft.isSafetyLocked && !draft.quadrant.isImportant {
                            Label("Safety & compliance items are normally kept important.", systemImage: "exclamationmark.shield")
                                .font(.footnote).foregroundStyle(Theme.warning)
                        }
                        ForEach(draft.classificationReasons, id: \.self) { reason in
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Eisenhower Matrix")
                    }

                    Section("Details") {
                        Picker("Category", selection: bind(\.category, .category)) {
                            ForEach(TaskCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                        }
                        Picker("Priority", selection: bind(\.priority, .priority)) {
                            ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                        }
                        if draft.kind == .followUp {
                            TextField("What they asked", text: $draft.request, axis: .vertical)
                            TextField("What I committed to", text: $draft.commitment, axis: .vertical)
                        }
                    }
                }
            }
            .navigationTitle("Adjust")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var defaultReminder: Date {
        let base = draft.dueDate ?? Date()
        let minutes = AppSettings.defaultReminderMinutes
        let candidate = DateMath(calendar: .current).date(on: base, minutes: minutes)
        return candidate > Date() ? candidate : Date().addingTimeInterval(3600)
    }

    private func bind<T>(_ keyPath: WritableKeyPath<CaptureDraft, T>, _ field: CaptureDraft.Field) -> Binding<T> {
        Binding(
            get: { draft[keyPath: keyPath] },
            set: { newValue in
                draft[keyPath: keyPath] = newValue
                draft.locked.insert(field)
            })
    }
}

/// 2×2 quadrant selector.
struct QuadrantPicker: View {
    @Binding var quadrant: Quadrant

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow { cell(.doFirst); cell(.schedule) }
            GridRow { cell(.delegate); cell(.eliminate) }
        }
        .padding(.vertical, 4)
    }

    private func cell(_ q: Quadrant) -> some View {
        Button {
            quadrant = q
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(q.code) · \(q.title)").font(.subheadline.weight(.semibold))
                Text(q.subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(8)
            .background(Theme.color(for: q).opacity(quadrant == q ? 0.28 : 0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.color(for: q).opacity(quadrant == q ? 0.9 : 0.2), lineWidth: quadrant == q ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(quadrant == q ? .isSelected : [])
    }
}

/// Edits a recurrence rule: none, daily, specific weekdays, monthly, with custom intervals.
struct RecurrenceEditor: View {
    @Binding var rule: RecurrenceRule?

    private enum Mode: String, CaseIterable, Identifiable {
        case none, daily, weekly, monthly
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "Does not repeat"
            case .daily: return "Daily"
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }
    }

    private var mode: Mode {
        guard let rule else { return .none }
        switch rule.frequency {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        }
    }

    var body: some View {
        Picker("Repeats", selection: Binding(get: { mode }, set: { setMode($0) })) {
            ForEach(Mode.allCases) { Text($0.title).tag($0) }
        }
        if let current = rule {
            Stepper(value: Binding(get: { current.interval }, set: { update(interval: $0) }), in: 1...12) {
                Text(intervalText(current))
            }
            if current.frequency == .weekly {
                weekdayToggles(current)
            }
            if current.frequency == .monthly {
                Stepper(value: Binding(get: { current.dayOfMonth ?? Calendar.current.component(.day, from: Date()) },
                                       set: { update(dayOfMonth: $0) }), in: 1...31) {
                    Text("On the \(RecurrenceRule.ordinal(current.dayOfMonth ?? Calendar.current.component(.day, from: Date())))")
                }
            }
            Text(current.summary(calendar: .current)).font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func intervalText(_ r: RecurrenceRule) -> String {
        let unit: String
        switch r.frequency {
        case .daily: unit = r.interval == 1 ? "day" : "days"
        case .weekly: unit = r.interval == 1 ? "week" : "weeks"
        case .monthly: unit = r.interval == 1 ? "month" : "months"
        }
        return "Every \(r.interval == 1 ? "" : "\(r.interval) ")\(unit)"
    }

    private func weekdayToggles(_ r: RecurrenceRule) -> some View {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        let order = [2, 3, 4, 5, 6, 7, 1]
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let selected = r.weekdays.contains(day)
                Button {
                    var days = Set(r.weekdays)
                    if selected { days.remove(day) } else { days.insert(day) }
                    if days.isEmpty { days.insert(day) }
                    rule = RecurrenceRule(frequency: .weekly, interval: r.interval, weekdays: Array(days), dayOfMonth: nil, endDate: r.endDate)
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .background(selected ? Theme.accent : Theme.surfaceRaised, in: Circle())
                        .foregroundStyle(selected ? Color.black : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private func setMode(_ m: Mode) {
        let today = Calendar.current.component(.weekday, from: Date())
        switch m {
        case .none: rule = nil
        case .daily: rule = .daily
        case .weekly: rule = .weekly(on: [today])
        case .monthly: rule = .monthly(day: Calendar.current.component(.day, from: Date()))
        }
    }

    private func update(interval: Int) {
        guard let r = rule else { return }
        rule = RecurrenceRule(frequency: r.frequency, interval: interval, weekdays: r.weekdays, dayOfMonth: r.dayOfMonth, endDate: r.endDate)
    }

    private func update(dayOfMonth: Int) {
        guard let r = rule else { return }
        rule = RecurrenceRule(frequency: r.frequency, interval: r.interval, weekdays: r.weekdays, dayOfMonth: dayOfMonth, endDate: r.endDate)
    }
}
