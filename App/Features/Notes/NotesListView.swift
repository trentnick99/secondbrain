import SwiftData
import SwiftUI
import SecondBrainCore

struct NotesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var search = ""
    @State private var typeFilter: NoteType?
    @State private var editing: Note?
    @State private var pendingDelete: Note?

    private var filtered: [Note] {
        notes.filter { n in
            (typeFilter == nil || n.type == typeFilter) && n.matches(search)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Chip(title: "All", isSelected: typeFilter == nil) { typeFilter = nil }
                            ForEach(NoteType.allCases) { type in
                                Chip(title: type.title, systemImage: type.systemImage, isSelected: typeFilter == type) {
                                    typeFilter = (typeFilter == type) ? nil : type
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                let pinned = filtered.filter(\.isPinned)
                let others = filtered.filter { !$0.isPinned }
                if !pinned.isEmpty {
                    Section("Pinned") { ForEach(pinned) { row($0) } }
                }
                if !others.isEmpty {
                    Section(pinned.isEmpty ? "Notes" : "Other notes") { ForEach(others) { row($0) } }
                }
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No notes yet" : "No matches", systemImage: "note.text",
                                           description: Text(search.isEmpty ? "Meeting notes, ideas, department and safety notes live here. Checklist items can become tasks." : "Try a different search."))
                        .listRowBackground(Color.clear)
                }
                Color.clear.frame(height: 72).listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Notes")
            .searchable(text: $search, prompt: "Search notes, tags, people")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(NoteType.allCases) { type in
                            Button { editing = newNote(type) } label: { Label("\(type.title) Note", systemImage: type.systemImage) }
                        }
                    } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("New note")
                }
            }
            .sheet(item: $editing) { note in
                NavigationStack { NoteEditorView(note: note) }
            }
            .confirmationDialog("Delete this note?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let note = pendingDelete { context.delete(note); TaskActions.save(context) }
                    pendingDelete = nil
                }
            } message: {
                Text("Linked tasks are kept.")
            }
        }
    }

    private func row(_ note: Note) -> some View {
        NavigationLink { NoteEditorView(note: note) } label: { NoteRow(note: note) }
            .swipeActions(edge: .leading) {
                Button {
                    note.isPinned.toggle()
                    TaskActions.save(context)
                } label: { Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin") }
                    .tint(Theme.warning)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = note } label: { Label("Delete", systemImage: "trash") }
            }
    }

    private func newNote(_ type: NoteType) -> Note {
        let note = Note(title: "", body: "", type: type)
        context.insert(note)
        return note
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: note.type.systemImage).foregroundStyle(Theme.accent).font(.caption)
                Text(note.displayTitle).font(.body.weight(.medium)).lineLimit(1)
                if note.isPinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.warning) }
            }
            if !note.snippet.isEmpty {
                Text(note.snippet).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 8) {
                Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                if let name = note.associate?.name { Text("· \(name)") }
                let open = (note.checklist ?? []).filter { !$0.isDone }.count
                if open > 0 { Text("· \(open) to do") }
                ForEach(note.tags.prefix(3), id: \.self) { Text("#\($0)").foregroundStyle(Theme.accent) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
