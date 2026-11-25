import SwiftUI
import SwiftData
import SecondBrainCore

/// Lists of work handed to each team lead, ready to text. Only task titles and due times are sent,
/// and you choose who gets it in the share sheet.
struct TeamListsView: View {
    @Query private var tasks: [TaskItem]
    @Query(filter: #Predicate<Associate> { !$0.isArchived }, sort: \Associate.name) private var associates: [Associate]
    @State private var newName = ""

    private var leads: [String] {
        associates.filter { $0.role.localizedCaseInsensitiveContains("lead") }.map(\.name)
    }

    var body: some View {
        let people = TeamLists.people(tasks: tasks.map(\.snapshot), leads: leads)
        List {
            Section {
                if people.isEmpty {
                    Text("Add your team leads under Associates with a role like “Stocking Team Lead”, or type a name below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(people, id: \.name) { person in
                    NavigationLink {
                        TeamListDetailView(name: person.name)
                    } label: {
                        LabeledContent(person.name, value: person.open == 0 ? "Nothing yet" : "\(person.open) open")
                    }
                }
            } footer: {
                Text("Handed-off tasks show here until they're done. Tasks you hand off wait for the person to confirm.")
            }
            Section("Someone else") {
                HStack {
                    TextField("Name", text: $newName)
                    NavigationLink("Open") { TeamListDetailView(name: newName.trimmingCharacters(in: .whitespaces)) }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Team lead lists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TeamListDetailView: View {
    let name: String
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]
    @State private var picking = false

    var body: some View {
        let theirs = TeamLists.tasks(for: name, in: tasks.map(\.snapshot))
        let items = theirs.compactMap { snap in tasks.first { $0.id == snap.id } }
        List {
            Section {
                if items.isEmpty {
                    Text("Nothing handed to \(name) yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                        if let due = task.dueDate {
                            Text(RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: Date(), calendar: .current))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button("Take back") {
                            task.delegatedTo = ""
                            task.delegationConfirmed = false
                            task.waitingOn = ""
                            if task.status == .waiting { task.status = .notStarted }
                            task.updatedAt = Date()
                            TaskActions.save(context)
                        }
                        .tint(Theme.warning)
                    }
                }
            } footer: {
                Text("Swipe to take a task back.")
            }
            Section {
                ShareLink(item: TeamLists.text(for: name, tasks: theirs, now: Date(), calendar: .current),
                          subject: Text("Your list"), preview: SharePreview("List for \(name)")) {
                    Label("Send list to \(name.split(separator: " ").first.map(String.init) ?? name)", systemImage: "message")
                }
                .disabled(theirs.isEmpty)
                Button { picking = true } label: { Label("Hand off tasks…", systemImage: "arrow.turn.up.right") }
            } footer: {
                Text("Only task titles and due times are sent. You pick who gets it.")
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $picking) { HandOffPicker(name: name) }
    }
}

/// Pick open tasks to hand to someone. Confirmed before anything changes.
private struct HandOffPicker: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]
    @State private var chosen: Set<UUID> = []
    @State private var confirming = false

    var body: some View {
        let candidates = tasks.filter { $0.status.isOpen && $0.delegatedTo.isEmpty && $0.kind != .followUp }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        NavigationStack {
            List(candidates) { task in
                Button {
                    if chosen.contains(task.id) { chosen.remove(task.id) } else { chosen.insert(task.id) }
                } label: {
                    HStack {
                        Image(systemName: chosen.contains(task.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen.contains(task.id) ? Theme.accent : .secondary)
                        Text(task.title).foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Hand off to \(name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hand off \(chosen.count)") { confirming = true }.disabled(chosen.isEmpty)
                }
            }
            .confirmationDialog("Hand \(chosen.count) task\(chosen.count == 1 ? "" : "s") to \(name)?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Hand off") {
                    for task in tasks where chosen.contains(task.id) {
                        TaskActions.delegate(task, to: name, in: context)
                    }
                    router.showToast("Handed off. Waiting for \(name) to confirm.")
                    dismiss()
                }
            } message: {
                Text("They'll show as waiting until \(name) confirms. Nothing is sent until you share the list.")
            }
        }
    }
}
