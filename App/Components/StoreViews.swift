import SwiftData
import SwiftUI
import SecondBrainCore

// MARK: - Weekly schedule

/// Pick each weekday's shift: 7–5, 10–8, 12–10, a custom time, or Off.
///
/// A custom time is edited inline under that day rather than in a second sheet: Settings is itself a
/// sheet, and a sheet presented from rows of a Form could dismiss Settings and drop you back on Home.
struct ScheduleEditor: View {
    @Binding var scheduleJSON: String
    var weekStartsOn: Int
    @State private var editingDay: Int?
    @State private var customStart = ShiftTime.opening.startMinutes
    @State private var customEnd = ShiftTime.opening.endMinutes

    private var schedule: ShiftSchedule { ScheduleStorage.decode(scheduleJSON) }

    private var weekdays: [Int] { (0..<7).map { ((weekStartsOn - 1 + $0) % 7) + 1 } }

    var body: some View {
        ForEach(weekdays, id: \.self) { weekday in
            row(weekday)
            if editingDay == weekday {
                customEditor(weekday)
            }
        }
        Text(summary)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var summary: String {
        let hours = schedule.shifts.compactMap { $0 }.reduce(0) { $0 + $1.lengthMinutes } / 60
        return "\(schedule.workdayCount) shifts · \(hours) hours a week"
    }

    private func dayName(_ weekday: Int) -> String { Calendar.current.weekdaySymbols[weekday - 1] }

    private func row(_ weekday: Int) -> some View {
        let shift = schedule.shift(forWeekday: weekday)
        return HStack {
            Text(dayName(weekday))
            Spacer()
            Menu {
                Button { update(weekday, nil) } label: { choiceLabel("Off", selected: shift == nil) }
                ForEach(ShiftTime.presets, id: \.self) { preset in
                    Button { update(weekday, preset) } label: { choiceLabel(preset.shortLabel, selected: shift == preset) }
                }
                Button { startCustom(weekday) } label: { Label("Custom…", systemImage: "clock") }
            } label: {
                Text(shift?.shortLabel ?? "Off")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 64)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(shift == nil ? Theme.surfaceRaised : Theme.accent.opacity(0.2), in: Capsule())
                    .foregroundStyle(shift == nil ? Color.secondary : Theme.accent)
            }
            .accessibilityLabel("\(dayName(weekday)) shift")
            .accessibilityValue(shift?.shortLabel ?? "Off")
        }
    }

    private func customEditor(_ weekday: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom time for \(dayName(weekday))")
                .font(.subheadline.weight(.semibold))
            DatePicker("Starts", selection: minutes($customStart), displayedComponents: .hourAndMinute)
            DatePicker("Ends", selection: minutes($customEnd), displayedComponents: .hourAndMinute)
            if customEnd <= customStart {
                Text("The end time needs to be after the start time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.warning)
            }
            HStack {
                Button("Cancel") { withAnimation { editingDay = nil } }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("customShiftCancel")
                Spacer()
                Button("Save") {
                    update(weekday, ShiftTime(startMinutes: customStart, endMinutes: customEnd))
                }
                .buttonStyle(.borderedProminent)
                .disabled(customEnd <= customStart)
                .accessibilityIdentifier("customShiftSave")
            }
        }
        .padding(.vertical, 4)
    }

    private func startCustom(_ weekday: Int) {
        let current = schedule.shift(forWeekday: weekday) ?? .opening
        customStart = current.startMinutes
        customEnd = current.endMinutes
        withAnimation { editingDay = weekday }
    }

    @ViewBuilder
    private func choiceLabel(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func update(_ weekday: Int, _ shift: ShiftTime?) {
        var s = schedule
        s.setShift(shift, forWeekday: weekday)
        scheduleJSON = ScheduleStorage.encode(s)
        // Saving, or picking a preset or Off from the menu, closes that day's custom editor.
        if editingDay == weekday { withAnimation { editingDay = nil } }
    }

    private func minutes(_ value: Binding<Int>) -> Binding<Date> {
        Binding(get: { DateMath(calendar: .current).date(on: Date(), minutes: value.wrappedValue) },
                set: { value.wrappedValue = DateMath(calendar: .current).minutesSinceMidnight($0) })
    }
}

// MARK: - Delegation

/// Hand a task to a team lead (or anyone). It stays "waiting" until you confirm they took it on.
struct DelegateSheet: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var people: [Associate]
    @State private var otherName = ""

    private var active: [Associate] { people.filter { !$0.isArchived } }
    private var teamLeads: [Associate] {
        active.filter { $0.storeRole == .teamLead }
            .sorted { ($0.department, $0.name) < ($1.department, $1.name) }
    }
    private var leaders: [Associate] {
        active.filter { $0.storeRole == .coach || $0.storeRole == .storeManager }
            .sorted { ($0.storeRole?.sortIndex ?? 9, $0.name) < ($1.storeRole?.sortIndex ?? 9, $1.name) }
    }
    private var associates: [Associate] { active.filter { $0.storeRole == .associate || $0.storeRole == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("“\(task.displayTitle)” will show as waiting until you confirm they've taken it on.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !teamLeads.isEmpty {
                    Section("Team Leads") { ForEach(teamLeads) { row($0) } }
                }
                if !leaders.isEmpty {
                    Section("Coaches & Store Manager") { ForEach(leaders) { row($0) } }
                }
                if !associates.isEmpty {
                    Section("Associates") { ForEach(associates) { row($0) } }
                }
                Section("Someone else") {
                    HStack {
                        TextField("Name or role", text: $otherName)
                            .textInputAutocapitalization(.words)
                        Button("Delegate") { assign(otherName, person: nil) }
                            .disabled(otherName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if teamLeads.isEmpty {
                    Section {
                        Label("Add your team leads in Associates › + › Add Several People to pick them here.", systemImage: "lightbulb")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Delegate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ person: Associate) -> some View {
        Button { assign(person.name, person: person) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).foregroundStyle(.primary)
                    if !person.roleLine.isEmpty {
                        Text(person.roleLine).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let load = person.allTasks.filter { $0.isOpen && $0.isAwaitingConfirmation }.count
                if load > 0 {
                    Text("\(load) waiting").font(.caption2).foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private func assign(_ rawName: String, person: Associate?) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if task.associate == nil, let person { task.associate = person }
        TaskActions.delegate(task, to: name, in: context)
        router.showToast("Handed to \(name) · waiting for confirmation")
        dismiss()
    }
}

// MARK: - Team setup

/// Add several team leads or associates at once (one name per line).
struct TeamSetupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var role: StoreRole = .teamLead
    @State private var area = StoreAreas.all.first ?? "Stocking"
    @State private var jobTitle = ""
    @State private var names = ""

    private var nameList: [String] {
        names.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Role", selection: $role) {
                        ForEach(StoreRole.allCases) { Text($0.title).tag($0) }
                    }
                    if role == .associate {
                        TextField("Job title (e.g. Stocker, Cashier)", text: $jobTitle)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(StoreAreas.associateTitles, id: \.self) { title in
                                    Chip(title: title, isSelected: jobTitle == title) { jobTitle = title }
                                }
                            }
                        }
                    }
                    Picker("Area", selection: $area) {
                        ForEach(StoreAreas.all, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section {
                    TextField("One name per line", text: $names, axis: .vertical)
                        .lineLimit(5...12)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Names")
                } footer: {
                    Text("First names are fine. People already in Associates are updated, not duplicated.")
                }
                Section { PrivacyReminder() }
            }
            .navigationTitle("Add Several People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(nameList.count)") { save() }.disabled(nameList.isEmpty)
                }
            }
        }
    }

    private func save() {
        let roleText = role == .associate ? (jobTitle.isEmpty ? "Associate" : jobTitle) : role.title
        var added = 0
        for name in nameList {
            if let existing = TaskActions.associate(named: name, createIfMissing: false, in: context) {
                if existing.role.isEmpty { existing.role = roleText }
                if existing.department.isEmpty { existing.department = area }
                existing.updatedAt = Date()
            } else {
                let person = Associate(name: name, department: area, role: roleText)
                context.insert(person)
                added += 1
            }
        }
        TaskActions.save(context)
        router.showToast("Added \(added) \(added == 1 ? "person" : "people")")
        dismiss()
    }
}
