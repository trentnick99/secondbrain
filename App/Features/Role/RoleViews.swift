import SwiftUI
import SwiftData
import SecondBrainCore

/// Role, primary area and extra areas — shared by onboarding and Settings. Stored as JSON.
struct RoleEditor: View {
    @Binding var roleJSON: String

    private var role: UserRole { RoleStorage.decode(roleJSON) ?? UserRole(role: .coach, areas: []) }

    private func update(_ change: (inout UserRole) -> Void) {
        var next = role
        change(&next)
        roleJSON = RoleStorage.encode(next)
    }

    var body: some View {
        Section {
            Picker("Role", selection: Binding(get: { role.role }, set: { value in update { $0.role = value } })) {
                ForEach([StoreRole.coach, .teamLead, .storeManager]) { Text($0.title).tag($0) }
            }
            .accessibilityIdentifier("rolePicker")
            if role.role != .storeManager {
                Picker("Your area", selection: Binding(
                    get: { role.primaryArea ?? "" },
                    set: { value in update { r in
                        r.areas.removeAll { $0 == value }
                        if r.areas.isEmpty { r.areas = [value] } else { r.areas[0] = value }
                    } }
                )) {
                    Text("Choose…").tag("")
                    ForEach(StoreAreas.all, id: \.self) { Text($0).tag($0) }
                }
                .accessibilityIdentifier("areaPicker")
            }
        } header: {
            Text("Your role")
        } footer: {
            Text(role.role == .storeManager
                 ? "Store managers see every area."
                 : "Used to suggest routines, sort the Season Planner, show “My area” and sort imported notes. It stays on this iPhone.")
        }

        if role.role != .storeManager, role.primaryArea != nil {
            Section {
                ForEach(extraChoices, id: \.self) { area in
                    Toggle(area, isOn: Binding(
                        get: { role.areas.dropFirst().contains(area) },
                        set: { on in update { r in
                            if on { if !r.areas.contains(area) { r.areas.append(area) } }
                            else if r.areas.first != area { r.areas.removeAll { $0 == area } }
                        } }
                    ))
                }
            } header: {
                Text("Also cover")
            } footer: {
                Text("Add other areas or departments you're responsible for, such as Seasonal or Electronics freight.")
            }
        }
    }

    private var extraChoices: [String] {
        (StoreAreas.all + StoreAreas.otherDepartments).filter { $0 != role.primaryArea }
    }
}

/// Settings › Your role.
struct RoleSettingsView: View {
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""

    var body: some View {
        Form {
            RoleEditor(roleJSON: $roleJSON)
            if let role = RoleStorage.decode(roleJSON), role.role == .storeManager || role.primaryArea != nil {
                Section {
                    NavigationLink {
                        RoutinesView()
                    } label: {
                        Label("Suggested routines for \(role.title)s", systemImage: "repeat")
                    }
                }
            }
        }
        .navigationTitle("Your role")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if roleJSON.isEmpty { roleJSON = RoleStorage.encode(UserRole(role: .coach, areas: [])) }
        }
    }
}

/// The role editor as a sheet (from Home), with its own navigation.
struct RoleSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RoleSettingsView()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Common routines for the person's role, added as recurring tasks only when tapped.
struct RoutinesView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @AppStorage(SettingsKey.routinesAdded, store: AppGroup.defaults) private var addedRaw = ""
    @State private var confirmAll = false

    var body: some View {
        let role = RoleStorage.decode(roleJSON) ?? UserRole(role: .coach)
        let added = SeasonPlanStore.keys(addedRaw)
        let suggestions = RolePlaybook.suggestions(for: role)
        let remaining = suggestions.filter { !added.contains($0.id) }
        List {
            Section {
                ForEach(suggestions) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.category == .safety || item.category == .compliance ? "exclamationmark.shield" : "repeat")
                            .foregroundStyle(item.category == .safety || item.category == .compliance ? Theme.warning : Theme.accent)
                            .frame(width: 30, height: 30)
                            .background(Theme.tint(item.category == .safety ? Theme.warning : Theme.accent, 0.16),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline)
                            Text([item.scheduleText, item.area.map(StoreAreas.shortName)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if added.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).accessibilityLabel("Added")
                        } else {
                            Button("Add") { add(item) }
                                .buttonStyle(.bordered).controlSize(.small)
                                .accessibilityLabel("Add \(item.title)")
                        }
                    }
                }
            } header: {
                Text(role.title)
            } footer: {
                Text(RolePlaybook.disclaimer + " Each one becomes a recurring task you can find under Tasks › ⋯ › Recurring.")
            }
            if remaining.count > 1 {
                Section {
                    Button("Add all \(remaining.count)") { confirmAll = true }
                }
            }
        }
        .navigationTitle("Suggested routines")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Add \(remaining.count) recurring tasks?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Add \(remaining.count)") { remaining.forEach(add) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(remaining.map { "• \($0.title) (\($0.scheduleText.lowercased()))" }.joined(separator: "\n"))
        }
    }

    private func add(_ item: RoutineSuggestion) {
        var draft = CaptureDraft()
        draft.rawText = item.title
        draft.title = item.title
        draft.kind = .task
        draft.category = item.category
        draft.department = item.area ?? ""
        draft.recurrence = item.recurrence
        draft.details = "Suggested routine — change or remove it any time."
        let classification = EisenhowerClassifier.classify(ClassificationInput(
            text: item.title, category: item.category, kind: .task, priority: .normal,
            dueDate: nil, hasDueTime: false, now: Date(), calendar: .current))
        draft.quadrant = classification.quadrant
        draft.classificationReasons = classification.reasons
        draft.isSafetyLocked = classification.isSafetyLocked
        _ = CaptureSaver.save(draft, in: context)
        var keys = SeasonPlanStore.keys(addedRaw)
        keys.insert(item.id)
        addedRaw = SeasonPlanStore.joined(keys)
    }
}

/// Which tasks count as "My area" in Tasks: your areas, plus store-wide items.
enum MyArea {
    static func belongs(_ task: TaskItem, to role: UserRole) -> Bool {
        task.department == StoreAreas.totalStore || role.covers(task.department)
    }
}
