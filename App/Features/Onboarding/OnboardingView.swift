import SwiftData
import SwiftUI
import UserNotifications
import SecondBrainCore

/// First-run walkthrough: the idea, your shift times, notification permission (explained first,
/// asked once), and a privacy note.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.hasCompletedOnboarding, store: AppGroup.defaults) private var hasCompletedOnboarding = false
    @AppStorage(SettingsKey.shiftSchedule, store: AppGroup.defaults) private var scheduleJSON = ""
    @AppStorage(SettingsKey.weekStartsOn, store: AppGroup.defaults) private var weekStartsOn = SettingsDefault.weekStartsOn
    @State private var page = 0
    @State private var notificationResult: String?
    @State private var addSample = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                howItWorks.tag(1)
                shift.tag(2)
                notifications.tag(3)
                privacy.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 4 { withAnimation { page += 1 } } else { finish() }
            } label: {
                Text(page < 4 ? "Continue" : "Start using Second Brain")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.accent)
        .interactiveDismissDisabled()
    }

    private func pageLayout<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                Text(title).font(.largeTitle.weight(.bold))
                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 60)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var welcome: some View {
        pageLayout(icon: "brain.head.profile", title: "Your second brain for every shift") {
            Text("Capture what people ask, what you promise and what you notice — in seconds — then get back to the floor.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                principle("Capture now", "bolt.fill")
                principle("Organize automatically", "tray.2.fill")
                principle("Prioritize intelligently", "square.grid.2x2.fill")
                principle("Remember later", "bell.fill")
                principle("Follow through", "checkmark.seal.fill")
            }
        }
    }

    private var howItWorks: some View {
        pageLayout(icon: "sparkles", title: "How it works") {
            step("1", "Tap + anywhere and type or speak: “Check with John tomorrow about his schedule.”")
            step("2", "Second Brain suggests the person, date, reminder and Eisenhower quadrant. If anything is unclear, it asks before saving — it never invents dates or people.")
            step("3", "Your dashboard, widgets and reminders keep it in front of you.")
            step("4", "At the end of the day, End My Shift shows what's done and carries the rest forward — nothing unfinished disappears.")
        }
    }

    private var shift: some View {
        pageLayout(icon: "clock.fill", title: "Your shifts") {
            Text("Set each day's shift so “end of shift”, your morning briefing and End My Shift line up with when you actually work.")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ScheduleEditor(scheduleJSON: $scheduleJSON, weekStartsOn: weekStartsOn)
            }
            .card()
            Picker("Week starts on", selection: $weekStartsOn) {
                ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) }
            }
            .pickerStyle(.menu)
            Text("Schedules change? Update it any time in Settings › Your schedule.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var notifications: some View {
        pageLayout(icon: "bell.badge.fill", title: "Reminders that arrive") {
            Text("Second Brain uses notifications on your iPhone for reminders, deadlines, still-open alerts and an optional daily briefing. They're scheduled on the device, so they work offline and when the app is closed.")
                .foregroundStyle(.secondary)
            Text("From a notification you can Mark Complete, Snooze or open the task.").foregroundStyle(.secondary)
            Button {
                Task {
                    let granted = await NotificationService.shared.requestPermissionIfNeeded()
                    notificationResult = granted ? "Notifications are on." : "Notifications are off — you can turn them on later in Settings."
                }
            } label: {
                Label("Allow Notifications", systemImage: "bell")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered)
            if let notificationResult {
                Text(notificationResult).font(.subheadline.weight(.medium))
            }
            Text("iOS asks only once. You can skip this and enable it later.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var privacy: some View {
        pageLayout(icon: "lock.shield.fill", title: "Private by design") {
            Text("Everything stays on your iPhone unless you export a backup or turn on iCloud sync. There's no account and no employer connection.")
                .foregroundStyle(.secondary)
            PrivacyReminder()
            Text("You can turn on Face ID lock and hide notification details in Settings.").font(.subheadline).foregroundStyle(.secondary)
            Toggle("Add fictional sample data to explore", isOn: $addSample)
        }
    }

    private func principle(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.headline)
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.2), in: Circle())
                .foregroundStyle(Theme.accent)
            Text(text)
        }
    }

    private func finish() {
        if addSample { SampleData.load(into: context) }
        hasCompletedOnboarding = true
        Task { await AppMaintenance.runForegroundUpkeep() }
    }
}
