import Foundation
import SwiftData
import SecondBrainCore

typealias Note = SchemaV1.Note

extension SchemaV1 {
    /// A note: general, associate, meeting, department, operational, safety or idea.
    /// Structured text (body + checklist) with tags, pinning and links to tasks and associates.
    @Model
    final class Note {
        var id: UUID = UUID()
        var title: String = ""
        var body: String = ""
        var typeRaw: String = NoteType.general.rawValue
        /// Comma-separated tags (kept simple for sync and search).
        var tagsRaw: String = ""
        var department: String = ""
        var isPinned: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var associate: Associate?

        /// Inverse of `TaskItem.notes`.
        var linkedTasks: [TaskItem]? = []

        @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.note)
        var checklist: [ChecklistItem]? = []

        init(title: String = "", body: String = "", type: NoteType = .general) {
            self.id = UUID()
            self.title = title
            self.body = body
            self.typeRaw = type.rawValue
            self.createdAt = Date()
            self.updatedAt = Date()
        }

        var type: NoteType {
            get { NoteType(rawValue: typeRaw) ?? .general }
            set { typeRaw = newValue.rawValue }
        }

        var tags: [String] {
            get {
                tagsRaw.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            set {
                tagsRaw = newValue.map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
        }

        var displayTitle: String {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let firstLine = body.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return firstLine.isEmpty ? "Untitled note" : String(firstLine.prefix(60))
        }

        var snippet: String {
            let text = body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            return String(text.prefix(140))
        }

        var sortedChecklist: [ChecklistItem] {
            (checklist ?? []).sorted { $0.sortIndex == $1.sortIndex ? $0.createdAt < $1.createdAt : $0.sortIndex < $1.sortIndex }
        }

        var openTasks: [TaskItem] { (linkedTasks ?? []).filter { $0.isOpen } }

        func matches(_ query: String) -> Bool {
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            guard !q.isEmpty else { return true }
            if title.lowercased().contains(q) || body.lowercased().contains(q) || tagsRaw.lowercased().contains(q) { return true }
            if let name = associate?.name.lowercased(), name.contains(q) { return true }
            return (checklist ?? []).contains { $0.text.lowercased().contains(q) }
        }
    }
}

/// Stated explicitly (SwiftData already implies it) so every file sees it, whatever order the compiler checks them in.
extension Note: Identifiable {}
