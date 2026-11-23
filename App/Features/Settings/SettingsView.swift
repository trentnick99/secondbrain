import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import SecondBrainCore

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router

    @AppStorage(SettingsKey.shiftStartMinutes, store: AppGroup.defaults) private var shiftStart = SettingsDefault.shiftStartMinutes
    @AppStorage(SettingsKey.shiftEndMinutes, store: AppGroup.defaults) private var shiftEnd = SettingsDefault.shiftEndMinutes
    @AppStorage(SettingsKey.weekStartsOn, store: AppGroup.defaults) private var weekStartsOn = SettingsDefault.weekStartsOn
    @AppStorage(SettingsKey.defaultReminderEnabled, store: AppGroup.defaults) private var defaultReminderEnabled = SettingsDefault.defaultReminderEnabled
    @AppStorage(SettingsKey.defaultReminderMinutes, store: AppGroup.defaults) private var defaultReminderMinutes = SettingsDefault.defaultReminderMinutes
    @AppStorage(SettingsKey.notifyReminders, store: AppGroup.defaults) private var notifyReminders = true
    @AppStorage(SettingsKey.notifyDeadlines, store: AppGroup.defaults) private var notifyDeadlines = true
    @AppStorage(SettingsKey.notifyOverdue, store: AppGroup.defaults) private var notifyOverdue = true
    @AppStorage(SettingsKey.notifyBriefing, store: AppGroup.defaults) private var notifyBriefing = true
    @AppStorage(SettingsKey.overdueGraceMinutes, store: AppGroup.defaults) private var overdueGrace = SettingsDefault.overdueGraceMinutes
    @AppStorage(SettingsKey.hidePreviews, store: AppGroup.defaults) private var hidePreviews = false
    @AppStorage(SettingsKey.showBadge, store: AppGroup.defaults) private var showBadge = true
    @AppStorage(SettingsKey.appLockEnabled, store: AppGroup.defaults) private var appLockEnabled = false
    @AppStorage(SettingsKey.smartSuggestions, store: AppGroup.defaults) private var smartSuggestions = true
    @AppStorage(SettingsKey.appleIntelligence, store: AppGroup.defaults) private var appleIntelligence = false
    @AppStorage(SettingsKey.calendarEnabled, store: AppGroup.defaults) private var calendarEnabled = false
    @AppStorage(SettingsKey.iCloudSync, store: AppGroup.defaults) private var iCloudSync = false
    @AppStorage(SettingsKey.autoBackup, store: AppGroup.defaults) private var autoBackup = true
    @AppStorage(SettingsKey.appearance, store: AppGroup.defaults) private var appearance = SettingsDefault.appearance

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var pendingCount = 0
    @State private var exportDocument: BackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var alertMessage: String?
    @State private var confirmDeleteAll = false
    @State private var confirmDeleteAllAgain = false
    @State private var showRecurring = false
    @State private var calendarService = CalendarService.shared

    var body: some View {
        NavigationStack {
            Form {
                shiftSection
                notificationSection
                privacySection
                intelligenceSection
                calendarSection
                dataSection
                Section {
                    Button { showRecurring = true } label: { Label("Recurring tasks", systemImage: "repeat") }
                    Button { router.open(.weeklyReview) } label: { Label("Weekly review", systemImage: "chart.bar.doc.horizontal") }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await refreshStatus() }
            .onChange(of: notifyReminders) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: notifyDeadlines) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: notifyOverdue) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: notifyBriefing) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: hidePreviews) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: showBadge) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: overdueGrace) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: shiftStart) { _, _ in NotificationService.shared.requestResync() }
            .onChange(of: shiftEnd) { _, _ in NotificationService.shared.requestResync() }
            .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .json,
                          defaultFilename: "SecondBrain-Backup-\(NotificationPlannerKey.today())") { result in
                if case .failure(let error) = result { alertMessage = "Export failed: \(error.localizedDescription)" }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                importBackup(result)
            }
            .alert("Second Brain", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(alertMessage ?? "") }
            .confirmationDialog("Delete all Second Brain data?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) { confirmDeleteAllAgain = true }
            } message: {
                Text("Export a backup first if you might want this data later.")
            }
            .confirmationDialog("This can't be undone.", isPresented: $confirmDeleteAllAgain, titleVisibility: .visible) {
                Button("Yes, delete all data", role: .destructive) {
                    BackupService.deleteEverything(in: context)
                    alertMessage = "All data deleted."
                }
            }
            .sheet(isPresented: $showRecurring) { RecurringListView() }
        }
    }

    // MARK: Sections

    private var shiftSection: some View {
        Section {
            DatePicker("Shift starts", selection: minutesBinding($shiftStart), displayedComponents: .hourAndMinute)
            DatePicker("Shift ends", selection: minutesBinding($shiftEnd), displayedComponents: .hourAndMinute)
            Picker("Week starts on", selection: $weekStartsOn) {
                ForEach(1...7, id: \.self) { day in Text(Calendar.current.weekdaySymbols[day - 1]).tag(day) }
            }
            Toggle("Default reminder for dated items", isOn: $defaultReminderEnabled)
            if defaultReminderEnabled {
                DatePicker("Default reminder time", selection: minutesBinding($defaultReminderMinutes), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Your shift")
        } footer: {
            Text("Used for “end of shift”, the daily briefing, “tomorrow morning” snoozes, and to read times like “at 3”. A default reminder is shown in Quick Capture before saving.")
        }
    }

    private var notificationSection: some View {
        Section {
            HStack {
                Label("Permission", systemImage: "bell.badge")
                Spacer()
                Text(statusText).foregroundStyle(.secondary)
            }
            switch notificationStatus {
            case .notDetermined:
                Button("Allow Notifications") {
                    Task { _ = await NotificationService.shared.requestPermissionIfNeeded(); await refreshStatus() }
                }
            case .denied:
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            default:
                EmptyView()
            }
            Toggle("Task reminders", isOn: $notifyReminders)
            Toggle("Deadline alerts", isOn: $notifyDeadlines)
            Toggle("Still-open alerts", isOn: $notifyOverdue)
            if notifyOverdue {
                Picker("Alert after a missed deadline", selection: $overdueGrace) {
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
            }
            Toggle("Daily briefing at shift start", isOn: $notifyBriefing)
            Toggle("App icon badge", isOn: $showBadge)
            if notificationStatus == .authorized || notificationStatus == .provisional {
                Button("Send a test notification") { Task { await NotificationService.shared.sendTest() } }
                LabeledContent("Scheduled now", value: "\(pendingCount)")
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Reminders are scheduled on your iPhone ahead of time, so they arrive without an internet connection and even when the app is closed. iOS allows up to 64 pending alerts; Second Brain keeps the soonest 60 and tops them up each time you open the app.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle(isOn: Binding(get: { appLockEnabled }, set: { on in
                if on {
                    Task {
                        if await AppLock.shared.verifyForEnabling() { appLockEnabled = true }
                        else { alertMessage = "Set up Face ID or a passcode on your iPhone to use app lock." }
                    }
                } else {
                    appLockEnabled = false
                }
            })) {
                Label("Lock with \(AppLock.shared.biometryName)", systemImage: "faceid")
            }
            Toggle(isOn: $hidePreviews) {
                Label("Hide task details in notifications", systemImage: "eye.slash")
            }
        } header: {
            Text("Privacy & security")
        } footer: {
            Text("Data is stored on this iPhone, protected by iOS data protection. Second Brain is a personal tool — it doesn't connect to any employer systems and never asks for work credentials.")
        }
    }

    private var intelligenceSection: some View {
        Section {
            Toggle("Smart suggestions", isOn: $smartSuggestions)
            Toggle("Apple Intelligence briefing", isOn: $appleIntelligence)
                .disabled(!BriefingAssistant.isAppleIntelligenceAvailable)
            Text(BriefingAssistant.availabilityText).font(.caption).foregroundStyle(.secondary)
        } header: {
            Text("Intelligence")
        } footer: {
            Text("Capture interpretation, Eisenhower suggestions, follow-up detection and reviews run on your iPhone with built-in rules — no account, subscription or internet needed. Suggestions never change anything until you confirm.")
        }
    }

    private var calendarSection: some View {
        Section {
            Toggle("Show Apple Calendar events", isOn: Binding(get: { calendarEnabled }, set: { on in
                if on {
                    Task {
                        var granted = calendarService.hasFullAccess
                        if !granted { granted = await calendarService.requestAccess() }
                        if granted {
                            calendarEnabled = true
                        } else {
                            calendarEnabled = false
                            alertMessage = "Calendar access wasn't granted. You can allow it in iOS Settings › Second Brain."
                        }
                    }
                } else {
                    calendarEnabled = false
                }
            }))
            LabeledContent("Status", value: calendarService.statusText)
            if calendarService.status == .denied {
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("Optional. Shows events in your planner and flags overlaps. Tasks are only added to Calendar when you tap “Add to Apple Calendar” on a task.")
        }
    }

    private var dataSection: some View {
        Section {
            Button { exportBackup() } label: { Label("Export backup…", systemImage: "square.and.arrow.up") }
            Button { showImporter = true } label: { Label("Restore from backup…", systemImage: "square.and.arrow.down") }
            Toggle("Daily automatic backup", isOn: $autoBackup)
            if autoBackup {
                let backups = BackupService.automaticBackups()
                LabeledContent("Saved backups", value: "\(backups.count)")
            }
            Toggle("iCloud sync (requires setup)", isOn: $iCloudSync)
            Button { loadSample() } label: { Label("Add fictional sample data", systemImage: "wand.and.stars") }
            Button(role: .destructive) { confirmDeleteAll = true } label: { Label("Delete all data…", systemImage: "trash") }
        } header: {
            Text("Data")
        } footer: {
            Text("Backups are JSON files you can save to Files, iCloud Drive or email. Automatic backups appear in the Files app under On My iPhone › Second Brain › Backups. Restoring merges: newer records win, nothing is deleted. iCloud sync needs the iCloud capability added when building (see Docs/SIGNING.md) and takes effect after relaunch; without it, data stays on this iPhone.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0")
            LabeledContent("Widgets data sharing", value: AppGroup.isAvailable ? "On" : "Unavailable in this build")
            Button("Replay welcome") { AppGroup.defaults.set(false, forKey: SettingsKey.hasCompletedOnboarding) }
        } header: {
            Text("About")
        } footer: {
            Text("Project Second Brain is an independent personal productivity app. It is not affiliated with, endorsed by, or connected to any employer or retailer. Sample data is fictional.")
        }
    }

    // MARK: Helpers

    private var statusText: String {
        switch notificationStatus {
        case .authorized: return "Allowed"
        case .denied: return "Off"
        case .provisional: return "Quiet"
        case .ephemeral: return "Temporary"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private func refreshStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
        pendingCount = await NotificationService.shared.pendingCount()
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { DateMath(calendar: .current).date(on: Date(), minutes: minutes.wrappedValue) },
            set: { minutes.wrappedValue = DateMath(calendar: .current).minutesSinceMidnight($0) })
    }

    private func exportBackup() {
        do {
            exportDocument = BackupDocument(data: try BackupService.makeBackup(from: context))
            showExporter = true
        } catch {
            alertMessage = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try BackupService.restore(data, into: context)
                RecurrenceService.materialize(in: context)
                alertMessage = summary.text
            } catch {
                alertMessage = "That file couldn't be restored: \(error.localizedDescription)"
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func loadSample() {
        SampleData.load(into: context)
        alertMessage = "Fictional sample data added. Delete individual items any time."
    }
}
