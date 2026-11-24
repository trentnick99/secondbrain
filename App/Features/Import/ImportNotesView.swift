import SwiftUI
import SwiftData
import UIKit
import SecondBrainCore

/// Paste a market manager's email or notes, review the action items sorted by area, and add the ones
/// you choose. Nothing is saved until you tap Add. Items for other areas are left out.
struct ImportNotesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Associate.name) private var associates: [Associate]
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""

    @State private var text: String
    @State private var result: NoteImport?
    @State private var selected: Set<Int> = []
    @State private var titles: [Int: String] = [:]
    @State private var saveOriginal = true
    @State private var showHiddenNote = false

    private let startsWithText: Bool

    init(initialText: String? = nil) {
        _text = State(initialValue: initialText ?? "")
        startsWithText = !(initialText ?? "").isEmpty
    }

    private var role: UserRole? {
        guard let role = RoleStorage.decode(roleJSON), role.seesWholeStore || role.primaryArea != nil else { return nil }
        return role
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result { review(result) } else { input }
            }
            .onAppear {
                // Text from Shortcuts or a link goes straight to review (still nothing saved until Add).
                if startsWithText && result == nil { read() }
            }
            .navigationTitle(result == nil ? "Import notes" : "Review items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result != nil {
                        Button("Back") { withAnimation { result = nil } }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    // MARK: Step 1 — paste

    private var input: some View {
        Form {
            Section {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste a market walk recap, visit follow-up or any notes with action items.")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("importTextEditor")
                }
                HStack {
                    Button {
                        if let pasted = UIPasteboard.general.string, !pasted.isEmpty { text = pasted }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("importPasteButton")
                    Spacer()
                    if !text.isEmpty {
                        Button("Clear", role: .destructive) { text = "" }.buttonStyle(.bordered)
                    }
                }
                SensitiveContentNotice(text: text)
            } footer: {
                Text("Only bring in what you're allowed to keep on a personal device. Everything stays on this iPhone.")
            }

            Section {
                Button {
                    read()
                } label: {
                    Label("Find action items", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("importReviewButton")
            } footer: {
                Text(role.map { "Sorted for \($0.title): your areas and total-store items. Items for other areas are left out." }
                     ?? "Tip: choose your role in Settings to sort items by area.")
            }
        }
    }

    private func read() {
        let ctx = AppSettings.captureContext(knownAssociates: associates.map(\.name))
        let parsed = NoteImporter.parse(text, role: role, context: ctx)
        selected = Set(parsed.items.filter { $0.relevance == .mine || $0.relevance == .totalStore }.map(\.id))
        titles = Dictionary(uniqueKeysWithValues: parsed.items.map { ($0.id, $0.parsed.title.isEmpty ? $0.text : $0.parsed.title) })
        withAnimation { result = parsed }
    }

    // MARK: Step 2 — review

    private func review(_ result: NoteImport) -> some View {
        let groups: [AreaRelevance] = [.mine, .totalStore, .unassigned]
        let hiddenCount = result.items(.other).count
        let chosen = result.items.filter { selected.contains($0.id) }
        return List {
            if let subject = result.subject {
                Section { Label(subject, systemImage: "envelope").font(.subheadline) }
            }
            if result.items.isEmpty {
                ContentUnavailableView("No action items found", systemImage: "text.magnifyingglass",
                                       description: Text("Try bullet points or lines like “Please fix the wet wall signage by Friday.”"))
            }
            ForEach(groups, id: \.self) { group in
                let items = result.items(group)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in row(item) }
                    } header: {
                        Text(group == .mine && role == nil ? "Items" : group.title)
                    } footer: {
                        if group == .unassigned { Text("These don't name an area. Tick any that are yours.") }
                    }
                }
            }
            if hiddenCount > 0 {
                Section {
                    Label("\(hiddenCount) item\(hiddenCount == 1 ? "" : "s") for other areas left out", systemImage: "eye.slash")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle("Also save the original as a note", isOn: $saveOriginal)
                Button {
                    save(chosen, result: result)
                } label: {
                    Text(chosen.isEmpty ? "Choose items to add" : "Add \(chosen.count) task\(chosen.count == 1 ? "" : "s")")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen.isEmpty && !saveOriginal)
                .accessibilityIdentifier("importAddButton")
            } footer: {
                Text("Dates are read only when the notes state them, relative to today. Check them before adding.")
            }
        }
    }

    private func row(_ item: ImportedItem) -> some View {
        let isOn = selected.contains(item.id)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if isOn { selected.remove(item.id) } else { selected.insert(item.id) }
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Theme.accent : .secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isOn ? "Selected" : "Not selected")
            VStack(alignment: .leading, spacing: 6) {
                TextField("Task", text: Binding(get: { titles[item.id] ?? item.text }, set: { titles[item.id] = $0 }), axis: .vertical)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    if let due = item.parsed.dueDate {
                        chip(RelativeDateText.dayLabel(for: due, now: Date(), calendar: .current), "calendar", Theme.accent)
                    }
                    if let area = item.filingArea {
                        chip(StoreAreas.shortName(area), item.isTotalStore ? "building.2" : "square.grid.2x2", Theme.purple)
                    }
                    QuadrantBadge(quadrant: item.parsed.classification.quadrant, compact: true)
                    if item.parsed.classification.isSafetyLocked {
                        Image(systemName: "exclamationmark.shield").font(.caption).foregroundStyle(Theme.warning)
                            .accessibilityLabel("Safety or compliance")
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func chip(_ text: String, _ icon: String, _ tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.tint(tint, 0.16), in: Capsule())
            .foregroundStyle(tint)
    }

    private func save(_ items: [ImportedItem], result: NoteImport) {
        let source = result.subject ?? "Imported notes"
        let stamp = Date().formatted(date: .abbreviated, time: .omitted)
        for item in items {
            var draft = CaptureDraft(parsed: item.parsed)
            let title = (titles[item.id] ?? item.parsed.title).trimmingCharacters(in: .whitespacesAndNewlines)
            draft.title = title.isEmpty ? item.text : title
            draft.details = ([draft.details, "From: \(source) (imported \(stamp))"].filter { !$0.isEmpty }).joined(separator: "\n")
            _ = CaptureSaver.save(draft, in: context)
        }
        if saveOriginal {
            let note = Note(title: source, body: text, type: .general)
            context.insert(note)
            try? context.save()
        }
        let count = items.count
        router.showToast(count == 0 ? "Saved the notes" : "Added \(count) task\(count == 1 ? "" : "s")")
        dismiss()
    }
}
