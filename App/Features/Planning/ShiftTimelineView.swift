import SwiftUI
import SwiftData
import UserNotifications
import SecondBrainCore

/// Today's shift hour by hour: your plan blocks plus tasks with a due time. Optional nudges when
/// each block starts. The plan is yours to edit.
struct ShiftTimelineView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskItem]
    @AppStorage(SettingsKey.userRole, store: AppGroup.defaults) private var roleJSON = ""
    @AppStorage(SettingsKey.shiftPlanBlocks, store: AppGroup.defaults) private var blocksJSON = ""
    @AppStorage(SettingsKey.shiftPlanNudges, store: AppGroup.defaults) private var nudges = false
    @State private var now = Date()

    private var window: (start: Date, end: Date)? { AppSettings.shiftWindow(on: now) }

    var body: some View {
        let blocks = ShiftPlanStorage.blocks(blocksJSON, role: RoleStorage.decode(roleJSON))
        NavigationStack {
            List {
                if let window {
                    let entries = ShiftPlan.entries(blocks: blocks, shiftStart: window.start, shiftEnd: window.end,
                                                    tasks: tasks.map(\.snapshot))
                    let current = ShiftPlan.current(entries, now: now)
                    Section {
                        Toggle("Nudge me when each block starts", isOn: $nudges)
                            .accessibilityIdentifier("timelineNudgesToggle")
                    } header: {
                        Text(timeRange(window.start, window.end))
                    } footer: {
                        Text("A quiet notification at the start of each block today and next shift.")
                    }
                    Section {
                        ForEach(entries) { entry in
                            TimelineRow(entry: entry, isNow: entry.id == current?.id, isPast: entry.end <= now)
                        }
                    } header: {
                        Text("Today")
                    }
                } else {
                    Section {
                        Label("No shift today. Your plan is ready for your next shift.", systemImage: "moon.zzz")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    NavigationLink {
                        ShiftPlanEditor(blocksJSON: $blocksJSON, role: RoleStorage.decode(roleJSON))
                    } label: {
                        Label("Edit my plan", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("timelineEditButton")
                } footer: {
                    Text("Blocks are placed from the start of your shift, so the plan works for 7–5, 10–8 and 12–10.")
                }
            }
            .navigationTitle("Shift timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onChange(of: nudges) { _, isOn in
                Task {
                    if isOn { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
                    await ShiftPlanNotifier.reschedule()
                }
            }
            .onChange(of: blocksJSON) { _, _ in Task { await ShiftPlanNotifier.reschedule() } }
            .task {
                while !Task.isCancelled {
                    now = Date()
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
        }
    }

    private func timeRange(_ start: Date, _ end: Date) -> String {
        "Shift " + start.formatted(date: .omitted, time: .shortened) + "–" + end.formatted(date: .omitted, time: .shortened)
    }
}

private struct TimelineRow: View {
    let entry: ShiftPlan.Entry
    let isNow: Bool
    let isPast: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(entry.start.formatted(date: .omitted, time: .shortened))
                .font(.subheadline.monospacedDigit().weight(isNow ? .bold : .regular))
                .foregroundStyle(isNow ? Theme.accent : .secondary)
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if entry.isTask {
                        Image(systemName: entry.isSafety ? "shield.lefthalf.filled" : "circle")
                            .foregroundStyle(entry.isSafety ? Theme.danger : Theme.accent)
                    }
                    Text(entry.title)
                        .font(isNow ? .headline : .body)
                        .foregroundStyle(isPast && !isNow ? .secondary : .primary)
                }
                if isNow {
                    Text("Now · until " + entry.end.formatted(date: .omitted, time: .shortened))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(isNow ? Theme.tint(Theme.accent, 0.15) : nil)
        .accessibilityElement(children: .combine)
    }
}

/// Edit the plan: titles, start times (relative to the shift start) and lengths.
private struct ShiftPlanEditor: View {
    @Binding var blocksJSON: String
    let role: UserRole?
    @State private var blocks: [PlanBlock] = []
    @State private var loaded = false
    @State private var confirmReset = false

    /// Today's shift start, or 7:00 when there's no shift today, so times read naturally.
    private var reference: Date {
        AppSettings.shiftWindow()?.start
            ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        List {
            Section {
                ForEach($blocks) { $block in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Block", text: $block.title)
                            .font(.headline)
                        HStack {
                            DatePicker("Starts", selection: Binding(
                                get: { reference.addingTimeInterval(TimeInterval(block.offsetMinutes * 60)) },
                                set: { block.offsetMinutes = max(0, Int($0.timeIntervalSince(reference) / 60)) }),
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Spacer()
                            Stepper("\(block.durationMinutes) min", value: $block.durationMinutes, in: 5...480, step: 15)
                                .fixedSize()
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { blocks.remove(atOffsets: $0) }
                Button {
                    let last = blocks.max { $0.offsetMinutes < $1.offsetMinutes }
                    blocks.append(PlanBlock(title: "New block", offsetMinutes: (last.map { $0.offsetMinutes + $0.durationMinutes }) ?? 0,
                                            durationMinutes: 30))
                } label: {
                    Label("Add a block", systemImage: "plus")
                }
            } footer: {
                Text("Swipe to delete. Start times move with your shift: a block at 7:30 on a 7–5 shift is at 10:30 on a 10–8.")
            }
            Section {
                Button("Use the suggested plan", role: .destructive) { confirmReset = true }
            }
        }
        .navigationTitle("My plan")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Replace your plan with the suggested one?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Replace", role: .destructive) {
                let minutes = AppSettings.shiftSchedule.shift(on: Date(), calendar: .current)?.lengthMinutes ?? 600
                blocks = ShiftPlan.defaultBlocks(for: role, shiftMinutes: minutes)
            }
        }
        .onAppear {
            guard !loaded else { return }
            blocks = ShiftPlanStorage.blocks(blocksJSON, role: role)
            loaded = true
        }
        .onChange(of: blocks) { _, new in
            guard loaded else { return }
            blocksJSON = JSONStorage.encode(new.sorted { $0.offsetMinutes < $1.offsetMinutes })
        }
    }
}

enum ShiftPlanStorage {
    static func blocks(_ json: String, role: UserRole?) -> [PlanBlock] {
        if let saved = JSONStorage.decode([PlanBlock].self, from: json), !saved.isEmpty { return saved }
        let minutes = AppSettings.shiftSchedule.shift(on: Date(), calendar: .current)?.lengthMinutes ?? 600
        return ShiftPlan.defaultBlocks(for: role, shiftMinutes: minutes)
    }
}

/// Schedules a quiet notification at the start of each plan block for today's and the next shift.
@MainActor
enum ShiftPlanNotifier {
    static let prefix = "timeline."

    static func reschedule(now: Date = Date()) async {
        // Task reminders share iOS's 64-notification limit with these nudges, so let them re-plan after.
        defer { Task { @MainActor in NotificationService.shared.requestResync() } }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard AppGroup.defaults.bool(forKey: SettingsKey.shiftPlanNudges), !PersistenceController.isUITesting else { return }
        let blocks = ShiftPlanStorage.blocks(AppGroup.defaults.string(forKey: SettingsKey.shiftPlanBlocks) ?? "",
                                             role: RoleStorage.decode(AppGroup.defaults.string(forKey: SettingsKey.userRole) ?? ""))
        let calendar = Calendar.current
        var scheduled = 0
        for dayOffset in 0..<7 where scheduled < 12 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let window = AppSettings.shiftWindow(on: day, calendar: calendar) else { continue }
            for entry in ShiftPlan.entries(blocks: blocks, shiftStart: window.start, shiftEnd: window.end, tasks: [])
            where entry.start > now && scheduled < 12 {
                let content = UNMutableNotificationContent()
                content.title = entry.title
                content.body = "Until " + entry.end.formatted(date: .omitted, time: .shortened)
                content.interruptionLevel = .passive
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.start)
                let request = UNNotificationRequest(identifier: prefix + "\(parts.year!)\(parts.month!)\(parts.day!)." + entry.id,
                                                    content: content,
                                                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                try? await center.add(request)
                scheduled += 1
            }
            if scheduled > 0 && dayOffset > 0 { break }   // today's remaining blocks and the next shift
        }
    }
}
