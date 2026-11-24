import PhotosUI
import SwiftUI
import SwiftData
import UIKit
import SecondBrainCore

/// How the notes come in. Walk notes are your own observations, so they aren't filtered by role.
enum ImportMode: Equatable {
    case paste, speak
}

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
    @State private var sortByRole: Bool
    @State private var showScanner = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isReadingPhoto = false
    @State private var photoMessage: String?
    @State private var speech = SpeechCaptureService()

    private let startsWithText: Bool
    private let mode: ImportMode

    init(initialText: String? = nil, mode: ImportMode = .paste) {
        _text = State(initialValue: initialText ?? "")
        _sortByRole = State(initialValue: mode != .speak)
        startsWithText = !(initialText ?? "").isEmpty
        self.mode = mode
    }

    /// The role used to sort items: none for walk notes, which are your own observations.
    private var role: UserRole? {
        guard sortByRole, let role = savedRole else { return nil }
        return role
    }

    private var savedRole: UserRole? {
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
                if mode == .speak && !startsWithText && !speech.isListening {
                    Task { await speech.start() }
                }
            }
            .onDisappear { speech.stop() }
            .onChange(of: speech.isListening) { wasListening, isListening in
                if wasListening && !isListening { addSpokenItems() }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await readPhotos(items) }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { pages in
                    showScanner = false
                    Task { await readImages(pages) }
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
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
                HStack(spacing: 8) {
                    Button {
                        if let pasted = UIPasteboard.general.string, !pasted.isEmpty { text = pasted }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("importPasteButton")
                    if DocumentScanner.isSupported {
                        Button { showScanner = true } label: { Label("Scan", systemImage: "doc.viewfinder") }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("importScanButton")
                    }
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 5, matching: .images) {
                        Label("Photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("importPhotoButton")
                    Spacer(minLength: 0)
                }
                .labelStyle(.titleAndIcon)
                if isReadingPhoto {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Reading the text…").font(.footnote).foregroundStyle(.secondary)
                    }
                } else if let photoMessage {
                    Text(photoMessage).font(.footnote).foregroundStyle(.secondary)
                }
                if !text.isEmpty {
                    Button("Clear", role: .destructive) { text = "" }.buttonStyle(.borderless)
                }
                SensitiveContentNotice(text: text)
            } footer: {
                Text("Paste, scan a page or pick a photo of notes or a whiteboard. Text is read on this iPhone, and photos aren't saved. Only bring in what you're allowed to keep on a personal device.")
            }

            Section {
                Button {
                    Task { await speech.toggle() }
                } label: {
                    Label(speech.isListening ? "Stop" : "Speak walk notes",
                          systemImage: speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.headline)
                        .foregroundStyle(speech.isListening ? Theme.danger : Theme.accent)
                }
                .accessibilityIdentifier("importSpeakButton")
                if speech.isListening {
                    Text(speech.transcript.isEmpty ? "Listening… say one thing per sentence." : speech.transcript)
                        .font(.subheadline)
                        .foregroundStyle(speech.transcript.isEmpty ? .secondary : .primary)
                }
                if case .unavailable(let message) = speech.state {
                    Text(message).font(.footnote).foregroundStyle(Theme.warning)
                }
            } header: {
                Text("Walk notes")
            } footer: {
                Text("Walk and talk: “Aisle 12 has holes. Dairy cooler door is leaking.” Each sentence becomes an item. Say “next item” to split, or pause and tap Stop.\(speech.isOnDevice ? " Recognized on this iPhone." : "")")
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
                if let savedRole {
                    Toggle("Only my areas (\(savedRole.seesWholeStore ? "whole store" : savedRole.areasSummary))", isOn: $sortByRole)
                }
            } footer: {
                Text(role.map { "Sorted for \($0.title): your areas and total-store items. Items for other areas are left out." }
                     ?? (savedRole == nil ? "Tip: choose your role in Settings to sort items by area."
                                          : "Every item is kept, whatever area it mentions."))
            }
        }
    }

    // MARK: Scan, photo and speech

    private func addSpokenItems() {
        let items = RecognizedText.walkNoteItems(from: speech.transcript)
        guard !items.isEmpty else { return }
        let lines = RecognizedText.bulleted(items)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? lines : text + "\n" + lines
        sortByRole = false
    }

    private func readPhotos(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        isReadingPhoto = true
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        photoItems = []
        await readImages(images)
    }

    private func readImages(_ images: [UIImage]) async {
        guard !images.isEmpty else {
            isReadingPhoto = false
            return
        }
        isReadingPhoto = true
        photoMessage = nil
        let found = await TextRecognizer.text(in: images)
        isReadingPhoto = false
        if found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            photoMessage = "No text found. Try a closer, well-lit photo."
        } else {
            text = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? found : text + "\n\n" + found
            photoMessage = "Text added below the existing notes. Check it, then tap Find action items."
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
