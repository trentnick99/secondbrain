import SwiftUI
import SwiftData
import SecondBrainCore

/// A 5-minute huddle built from today: safety, yesterday, today's top three, shout-outs, questions.
/// Read it from the phone or share it. Nothing is saved unless you tap Save to Notes.
struct HuddleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var tasks: [TaskItem]
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @State private var shoutOuts = ""
    @State private var safetyOffset = 0

    private var script: HuddleScript {
        Huddle.build(tasks: tasks.map(\.snapshot), role: RoleStorage.decode(roleJSON), now: Date(),
                     calendar: .current, safetyOffset: safetyOffset, shoutOuts: shoutOuts)
    }

    var body: some View {
        let script = script
        NavigationStack {
            List {
                Section {
                    Text(script.heading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(script.sections) { section in
                    Section {
                        if section.title == "Shout-outs" {
                            TextField("Name and why, one per line", text: $shoutOuts, axis: .vertical)
                                .lineLimit(2...6)
                                .accessibilityIdentifier("huddleShoutOuts")
                            if shoutOuts.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(section.lines.first ?? "").foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.title3)
                            }
                        }
                        if section.title == "Safety" {
                            Button { safetyOffset += 1 } label: {
                                Label("Another safety message", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .font(.subheadline)
                        }
                    } header: {
                        Text(section.title)
                    }
                }
                Section {
                    ShareLink(item: script.text, subject: Text("Huddle"), preview: SharePreview("Huddle")) {
                        Label("Share with your team leads", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("huddleShareButton")
                    Button {
                        let note = Note(title: "Huddle · " + RelativeDateText.mediumDate(Date(), calendar: .current),
                                        body: script.text, type: .operational)
                        note.tagsRaw = "huddle"
                        context.insert(note)
                        try? context.save()
                        router.showToast("Huddle saved to Notes")
                    } label: {
                        Label("Save to Notes", systemImage: "square.and.arrow.down")
                    }
                } footer: {
                    Text("Today's top three come from your priorities. Change them on Home. Shout-outs are kept only if you save the huddle.")
                }
            }
            .navigationTitle("Huddle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
