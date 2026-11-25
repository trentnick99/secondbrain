import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Backup file format (JSON, versioned, human-readable)

struct BackupFile: Codable {
    static let currentVersion = 1

    var formatVersion: Int = BackupFile.currentVersion
    var exportedAt: Date = Date()
    var appVersion: String = ""
    var tasks: [TaskDTO] = []
    var associates: [AssociateDTO] = []
    var notes: [NoteDTO] = []
    var checklist: [ChecklistDTO] = []
    var series: [SeriesDTO] = []
    var activity: [ActivityDTO] = []
    var shiftLogs: [ShiftLogDTO] = []

    struct TaskDTO: Codable {
        var id: UUID; var title: String; var details: String; var kindRaw: String; var statusRaw: String
        var priorityRaw: String; var categoryRaw: String; var isUrgent: Bool; var isImportant: Bool
        var classificationIsManual: Bool; var classificationReasons: String; var department: String
        var dueDate: Date?; var hasDueTime: Bool; var reminderDate: Date?; var focusDate: Date?; var focusRank: Int
        var rescheduleCount: Int; var delegatedTo: String; var delegationConfirmed: Bool; var waitingOn: String
        var request: String; var commitment: String; var conversationDate: Date?; var seriesID: UUID?
        var occurrenceKey: String; var linkedFollowUpID: UUID?; var calendarEventID: String; var captureText: String
        var completionNotes: String; var createdAt: Date; var updatedAt: Date; var completedAt: Date?
        var archivedAt: Date?; var sortOrder: Double; var associateID: UUID?; var noteIDs: [UUID]
    }

    struct AssociateDTO: Codable {
        var id: UUID; var name: String; var department: String; var role: String; var profileNote: String
        var isArchived: Bool; var isFavorite: Bool; var createdAt: Date; var updatedAt: Date; var lastInteractionAt: Date?
    }

    struct NoteDTO: Codable {
        var id: UUID; var title: String; var body: String; var typeRaw: String; var tagsRaw: String
        var department: String; var isPinned: Bool; var createdAt: Date; var updatedAt: Date; var associateID: UUID?
    }

    struct ChecklistDTO: Codable {
        var id: UUID; var text: String; var isDone: Bool; var sortIndex: Int; var createdAt: Date
        var convertedTaskID: UUID?; var taskID: UUID?; var noteID: UUID?
    }

    struct SeriesDTO: Codable {
        var id: UUID; var title: String; var details: String; var kindRaw: String; var categoryRaw: String
        var priorityRaw: String; var isUrgent: Bool; var isImportant: Bool; var classificationIsManual: Bool
        var department: String; var ruleJSON: String; var anchorDate: Date; var hasTime: Bool; var timeMinutes: Int
        var remind: Bool; var isPaused: Bool; var isDiscontinued: Bool; var skippedKeys: String
        var lastGeneratedKey: String; var createdAt: Date; var updatedAt: Date; var associateID: UUID?
    }

    struct ActivityDTO: Codable {
        var id: UUID; var date: Date; var kindRaw: String; var isInteraction: Bool; var summary: String
        var taskID: UUID?; var associateID: UUID?
    }

    struct ShiftLogDTO: Codable {
        var id: UUID; var day: Date; var endedAt: Date; var completedCount: Int; var carriedForwardCount: Int
        var openCommitments: Int; var reflection: String
    }
}

struct RestoreSummary {
    var inserted = 0
    var updated = 0
    var skipped = 0
    var text: String { "Restored: \(inserted) added, \(updated) updated, \(skipped) already current." }
}

/// Export / import of everything in the store, plus a daily automatic backup in the app's
/// Documents folder (visible in the Files app under On My iPhone › Coach Spark).
@MainActor
enum BackupService {
    static func makeBackup(from context: ModelContext) throws -> Data {
        var file = BackupFile()
        file.appVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        file.tasks = tasks.map { t in
            BackupFile.TaskDTO(id: t.id, title: t.title, details: t.details, kindRaw: t.kindRaw, statusRaw: t.statusRaw,
                               priorityRaw: t.priorityRaw, categoryRaw: t.categoryRaw, isUrgent: t.isUrgent,
                               isImportant: t.isImportant, classificationIsManual: t.classificationIsManual,
                               classificationReasons: t.classificationReasons, department: t.department,
                               dueDate: t.dueDate, hasDueTime: t.hasDueTime, reminderDate: t.reminderDate,
                               focusDate: t.focusDate, focusRank: t.focusRank, rescheduleCount: t.rescheduleCount,
                               delegatedTo: t.delegatedTo, delegationConfirmed: t.delegationConfirmed, waitingOn: t.waitingOn,
                               request: t.request, commitment: t.commitment, conversationDate: t.conversationDate,
                               seriesID: t.seriesID, occurrenceKey: t.occurrenceKey, linkedFollowUpID: t.linkedFollowUpID,
                               calendarEventID: t.calendarEventID, captureText: t.captureText,
                               completionNotes: t.completionNotes, createdAt: t.createdAt, updatedAt: t.updatedAt,
                               completedAt: t.completedAt, archivedAt: t.archivedAt, sortOrder: t.sortOrder,
                               associateID: t.associate?.id, noteIDs: (t.notes ?? []).map(\.id))
        }
        file.associates = try context.fetch(FetchDescriptor<Associate>()).map { a in
            BackupFile.AssociateDTO(id: a.id, name: a.name, department: a.department, role: a.role,
                                    profileNote: a.profileNote, isArchived: a.isArchived, isFavorite: a.isFavorite,
                                    createdAt: a.createdAt, updatedAt: a.updatedAt, lastInteractionAt: a.lastInteractionAt)
        }
        file.notes = try context.fetch(FetchDescriptor<Note>()).map { n in
            BackupFile.NoteDTO(id: n.id, title: n.title, body: n.body, typeRaw: n.typeRaw, tagsRaw: n.tagsRaw,
                               department: n.department, isPinned: n.isPinned, createdAt: n.createdAt,
                               updatedAt: n.updatedAt, associateID: n.associate?.id)
        }
        file.checklist = try context.fetch(FetchDescriptor<ChecklistItem>()).map { c in
            BackupFile.ChecklistDTO(id: c.id, text: c.text, isDone: c.isDone, sortIndex: c.sortIndex, createdAt: c.createdAt,
                                    convertedTaskID: c.convertedTaskID, taskID: c.task?.id, noteID: c.note?.id)
        }
        file.series = try context.fetch(FetchDescriptor<RecurrenceSeries>()).map { s in
            BackupFile.SeriesDTO(id: s.id, title: s.title, details: s.details, kindRaw: s.kindRaw, categoryRaw: s.categoryRaw,
                                 priorityRaw: s.priorityRaw, isUrgent: s.isUrgent, isImportant: s.isImportant,
                                 classificationIsManual: s.classificationIsManual, department: s.department,
                                 ruleJSON: s.ruleJSON, anchorDate: s.anchorDate, hasTime: s.hasTime,
                                 timeMinutes: s.timeMinutes, remind: s.remind, isPaused: s.isPaused,
                                 isDiscontinued: s.isDiscontinued, skippedKeys: s.skippedKeys,
                                 lastGeneratedKey: s.lastGeneratedKey, createdAt: s.createdAt, updatedAt: s.updatedAt,
                                 associateID: s.associate?.id)
        }
        file.activity = try context.fetch(FetchDescriptor<ActivityEvent>()).map { e in
            BackupFile.ActivityDTO(id: e.id, date: e.date, kindRaw: e.kindRaw, isInteraction: e.isInteraction,
                                   summary: e.summary, taskID: e.task?.id, associateID: e.associate?.id)
        }
        file.shiftLogs = try context.fetch(FetchDescriptor<ShiftLog>()).map { l in
            BackupFile.ShiftLogDTO(id: l.id, day: l.day, endedAt: l.endedAt, completedCount: l.completedCount,
                                   carriedForwardCount: l.carriedForwardCount, openCommitments: l.openCommitments,
                                   reflection: l.reflection)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupFile.self, from: data)
    }

    /// Merges a backup into the store: new records are added, records that are newer in the backup
    /// replace older local copies, and nothing local is deleted.
    @discardableResult
    static func restore(_ data: Data, into context: ModelContext) throws -> RestoreSummary {
        let file = try decode(data)
        var summary = RestoreSummary()

        var associates: [UUID: Associate] = [:]
        for a in try context.fetch(FetchDescriptor<Associate>()) { associates[a.id] = a }
        for dto in file.associates {
            if let existing = associates[dto.id] {
                guard dto.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                fill(existing, dto); summary.updated += 1
            } else {
                let a = Associate(name: dto.name)
                fill(a, dto)
                context.insert(a)
                associates[dto.id] = a
                summary.inserted += 1
            }
        }

        var notes: [UUID: Note] = [:]
        for n in try context.fetch(FetchDescriptor<Note>()) { notes[n.id] = n }
        for dto in file.notes {
            let note: Note
            if let existing = notes[dto.id] {
                guard dto.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                note = existing; summary.updated += 1
            } else {
                note = Note()
                context.insert(note)
                notes[dto.id] = note
                summary.inserted += 1
            }
            note.id = dto.id; note.title = dto.title; note.body = dto.body; note.typeRaw = dto.typeRaw
            note.tagsRaw = dto.tagsRaw; note.department = dto.department; note.isPinned = dto.isPinned
            note.createdAt = dto.createdAt; note.updatedAt = dto.updatedAt
            note.associate = dto.associateID.flatMap { associates[$0] }
        }

        var series: [UUID: RecurrenceSeries] = [:]
        for s in try context.fetch(FetchDescriptor<RecurrenceSeries>()) { series[s.id] = s }
        for dto in file.series {
            let s: RecurrenceSeries
            if let existing = series[dto.id] {
                guard dto.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                s = existing; summary.updated += 1
            } else {
                s = RecurrenceSeries(title: dto.title, rule: .daily, anchorDate: dto.anchorDate)
                context.insert(s)
                series[dto.id] = s
                summary.inserted += 1
            }
            s.id = dto.id; s.title = dto.title; s.details = dto.details; s.kindRaw = dto.kindRaw
            s.categoryRaw = dto.categoryRaw; s.priorityRaw = dto.priorityRaw; s.isUrgent = dto.isUrgent
            s.isImportant = dto.isImportant; s.classificationIsManual = dto.classificationIsManual
            s.department = dto.department; s.ruleJSON = dto.ruleJSON; s.anchorDate = dto.anchorDate
            s.hasTime = dto.hasTime; s.timeMinutes = dto.timeMinutes; s.remind = dto.remind; s.isPaused = dto.isPaused
            s.isDiscontinued = dto.isDiscontinued; s.skippedKeys = dto.skippedKeys; s.lastGeneratedKey = dto.lastGeneratedKey
            s.createdAt = dto.createdAt; s.updatedAt = dto.updatedAt
            s.associate = dto.associateID.flatMap { associates[$0] }
        }

        var tasks: [UUID: TaskItem] = [:]
        for t in try context.fetch(FetchDescriptor<TaskItem>()) { tasks[t.id] = t }
        for dto in file.tasks {
            let t: TaskItem
            if let existing = tasks[dto.id] {
                guard dto.updatedAt > existing.updatedAt else { summary.skipped += 1; continue }
                t = existing; summary.updated += 1
            } else {
                t = TaskItem(title: dto.title)
                context.insert(t)
                tasks[dto.id] = t
                summary.inserted += 1
            }
            fill(t, dto)
            t.associate = dto.associateID.flatMap { associates[$0] }
            t.notes = dto.noteIDs.compactMap { notes[$0] }
        }

        let existingChecklistItem = try context.fetch(FetchDescriptor<ChecklistItem>())
        var checklistIDs = Set(existingChecklistItem.map(\.id))
        for dto in file.checklist where !checklistIDs.contains(dto.id) {
            let item = ChecklistItem(text: dto.text, sortIndex: dto.sortIndex)
            item.id = dto.id; item.isDone = dto.isDone; item.createdAt = dto.createdAt
            item.convertedTaskID = dto.convertedTaskID
            context.insert(item)
            item.task = dto.taskID.flatMap { tasks[$0] }
            item.note = dto.noteID.flatMap { notes[$0] }
            checklistIDs.insert(dto.id)
            summary.inserted += 1
        }

        let existingActivityEvent = try context.fetch(FetchDescriptor<ActivityEvent>())
        var activityIDs = Set(existingActivityEvent.map(\.id))
        for dto in file.activity where !activityIDs.contains(dto.id) {
            let e = ActivityEvent(kind: .edited, summary: dto.summary, date: dto.date)
            e.id = dto.id; e.kindRaw = dto.kindRaw; e.isInteraction = dto.isInteraction
            context.insert(e)
            e.task = dto.taskID.flatMap { tasks[$0] }
            e.associate = dto.associateID.flatMap { associates[$0] }
            activityIDs.insert(dto.id)
        }

        let existingShiftLog = try context.fetch(FetchDescriptor<ShiftLog>())
        var logIDs = Set(existingShiftLog.map(\.id))
        for dto in file.shiftLogs where !logIDs.contains(dto.id) {
            let log = ShiftLog(day: dto.day)
            log.id = dto.id; log.endedAt = dto.endedAt; log.completedCount = dto.completedCount
            log.carriedForwardCount = dto.carriedForwardCount; log.openCommitments = dto.openCommitments
            log.reflection = dto.reflection
            context.insert(log)
            logIDs.insert(dto.id)
        }

        TaskActions.save(context)
        return summary
    }

    private static func fill(_ a: Associate, _ dto: BackupFile.AssociateDTO) {
        a.id = dto.id; a.name = dto.name; a.department = dto.department; a.role = dto.role
        a.profileNote = dto.profileNote; a.isArchived = dto.isArchived; a.isFavorite = dto.isFavorite
        a.createdAt = dto.createdAt; a.updatedAt = dto.updatedAt; a.lastInteractionAt = dto.lastInteractionAt
    }

    private static func fill(_ t: TaskItem, _ dto: BackupFile.TaskDTO) {
        t.id = dto.id; t.title = dto.title; t.details = dto.details; t.kindRaw = dto.kindRaw; t.statusRaw = dto.statusRaw
        t.priorityRaw = dto.priorityRaw; t.categoryRaw = dto.categoryRaw; t.isUrgent = dto.isUrgent
        t.isImportant = dto.isImportant; t.classificationIsManual = dto.classificationIsManual
        t.classificationReasons = dto.classificationReasons; t.department = dto.department; t.dueDate = dto.dueDate
        t.hasDueTime = dto.hasDueTime; t.reminderDate = dto.reminderDate; t.focusDate = dto.focusDate
        t.focusRank = dto.focusRank; t.rescheduleCount = dto.rescheduleCount; t.delegatedTo = dto.delegatedTo
        t.delegationConfirmed = dto.delegationConfirmed; t.waitingOn = dto.waitingOn; t.request = dto.request
        t.commitment = dto.commitment; t.conversationDate = dto.conversationDate; t.seriesID = dto.seriesID
        t.occurrenceKey = dto.occurrenceKey; t.linkedFollowUpID = dto.linkedFollowUpID
        t.calendarEventID = dto.calendarEventID; t.captureText = dto.captureText; t.completionNotes = dto.completionNotes
        t.createdAt = dto.createdAt; t.updatedAt = dto.updatedAt; t.completedAt = dto.completedAt
        t.archivedAt = dto.archivedAt; t.sortOrder = dto.sortOrder
    }

    // MARK: Automatic daily backup

    static var backupsFolder: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let folder = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes today's backup (overwriting earlier ones from today) and keeps the 14 most recent.
    static func writeAutomaticBackup(from context: ModelContext) {
        guard AppSettings.autoBackup, !PersistenceController.isUITesting, let folder = backupsFolder,
              let data = try? makeBackup(from: context) else { return }
        let name = "SecondBrain-\(NotificationPlannerKey.today()).json"
        try? data.write(to: folder.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix("SecondBrain-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(14) { try? FileManager.default.removeItem(at: old) }
    }

    static func automaticBackups() -> [URL] {
        guard let folder = backupsFolder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Permanently removes all records (requires double confirmation in the UI).
    static func deleteEverything(in context: ModelContext) {
        try? context.delete(model: ActivityEvent.self)
        try? context.delete(model: ChecklistItem.self)
        try? context.delete(model: TaskItem.self)
        try? context.delete(model: Note.self)
        try? context.delete(model: RecurrenceSeries.self)
        try? context.delete(model: Associate.self)
        try? context.delete(model: ShiftLog.self)
        TaskActions.save(context)
    }
}

enum NotificationPlannerKey {
    static func today() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

/// Lets SwiftUI's file exporter write a backup.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
