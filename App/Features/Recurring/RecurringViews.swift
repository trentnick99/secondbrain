import SwiftData
import SwiftUI
import SecondBrainCore

/// Manage recurring responsibilities: edit, pause, resume, discontinue.
struct RecurringListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecurrenceSeries.title) private var series: [RecurrenceSeries]
    @State private var newSeries: RecurrenceSeries?

    var body: some View {
        NavigationStack {
            List {
                let active = series.filter { !$0.isDiscontinued }
                let ended = series.filter(\.isDiscontinued)
                if series.isEmpty {
                    ContentUnavailableView("No recurring tasks", systemImage: "repeat",
                                           description: Text("Capture “Remind me every Monday to review safety observations” or add one here."))
                }
                if !active.isEmpty {
                    Section("Active") {
                        ForEach(active) { s in
                            NavigationLink { SeriesEditorView(series: s) } label: { SeriesRow(series: s) }
                        }
                    }
                }
                if !ended.isEmpty {
                    Section("Discontinued") {
                        ForEach(ended) { s in
                            NavigationLink { SeriesEditorView(series: s) } label: { SeriesRow(series: s) }
                        }
                    }
                }
            }
            .navigationTitle("Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        let s = RecurrenceSeries(title: "", rule: .weekly(on: [Calendar.current.component(.weekday, from: Date())]),
                                                 anchorDate: Calendar.current.startOfDay(for: Date()))
                        s.isPaused = true   // stays inert until saved
                        context.insert(s)
                        newSeries = s
                    } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New recurring task")
                }
            }
            .sheet(item: $newSeries) { s in
                NavigationStack { SeriesEditorView(series: s, isNew: true) }
            }
        }
    }
}

struct SeriesRow: View {
    let series: RecurrenceSeries
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(series.title.isEmpty ? "Untitled" : series.title).font(.body.weight(.medium))
                if series.isPaused && !series.isDiscontinued {
                    Text("Paused").font(.caption2.weight(.bold)).foregroundStyle(Theme.warning)
                }
            }
            Text(series.summary()).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SeriesEditorView: View {
    @Bindable var series: RecurrenceSeries
    var isNew: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Associate.name) private var associates: [Associate]
    @State private var rule: RecurrenceRule?
    @State private var confirmDiscontinue = false
    @State private var saved = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $series.title)
                TextField("Details", text: $series.details, axis: .vertical)
                Picker("Category", selection: $series.category) {
                    ForEach(TaskCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                Picker("Priority", selection: $series.priority) {
                    ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                }
                Picker("Associate", selection: Binding(get: { series.associate?.id }, set: { id in series.associate = associates.first { $0.id == id } })) {
                    Text("None").tag(UUID?.none)
                    ForEach(associates.filter { !$0.isArchived }) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("Schedule") {
                RecurrenceEditor(rule: $rule)
                DatePicker("Starts", selection: $series.anchorDate, displayedComponents: [.date])
                Toggle("At a specific time", isOn: $series.hasTime)
                if series.hasTime {
                    DatePicker("Time", selection: Binding(
                        get: { DateMath(calendar: .current).date(on: Date(), minutes: series.timeMinutes) },
                        set: { series.timeMinutes = DateMath(calendar: .current).minutesSinceMidnight($0) }),
                               displayedComponents: [.hourAndMinute])
                }
                Toggle("Remind me", isOn: $series.remind)
            }
            Section {
                QuadrantPicker(quadrant: Binding(get: { series.quadrant }, set: { series.quadrant = $0; series.classificationIsManual = true }))
                if series.classificationIsManual {
                    Button("Use automatic suggestion per occurrence") { series.classificationIsManual = false }
                        .font(.footnote)
                }
            } header: {
                Text("Eisenhower Matrix")
            }
            if !isNew {
                Section {
                    if series.isDiscontinued {
                        Text("Discontinued. Past occurrences and their history are kept.").foregroundStyle(.secondary)
                    } else if series.isPaused {
                        Button("Resume") { RecurrenceService.resume(series, in: context) }
                    } else {
                        Button("Pause") { RecurrenceService.pause(series, in: context) }
                    }
                    if !series.isDiscontinued {
                        Button("Discontinue…", role: .destructive) { confirmDiscontinue = true }
                    }
                } footer: {
                    Text("Pausing or discontinuing removes future occurrences you haven't touched. Unfinished past occurrences stay on your list.")
                }
                Section("Recent occurrences") {
                    ForEach(RecurrenceService.occurrences(of: series, in: context).suffix(10).reversed()) { task in
                        NavigationLink { TaskDetailView(task: task) } label: { TaskRowView(task: task, showQuadrant: false) }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "New Recurring Task" : "Recurring Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(series.title.trimmingCharacters(in: .whitespaces).isEmpty || rule == nil)
            }
        }
        .onAppear { if rule == nil { rule = series.rule } }
        .onDisappear {
            // A new series dismissed without saving is removed rather than left behind.
            if isNew && !saved && series.modelContext != nil {
                context.delete(series)
                TaskActions.save(context)
            }
        }
        .confirmationDialog("Discontinue this recurring task?", isPresented: $confirmDiscontinue, titleVisibility: .visible) {
            Button("Discontinue", role: .destructive) { RecurrenceService.discontinue(series, in: context) }
        }
    }

    private func save() {
        if let rule { series.rule = rule }
        series.anchorDate = Calendar.current.startOfDay(for: series.anchorDate)
        if isNew { series.isPaused = false }
        RecurrenceService.applyEdits(series, in: context)
        saved = true
    }
}
