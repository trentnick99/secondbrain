import AppIntents
import SwiftUI
import WidgetKit
import SecondBrainCore

@main
struct SecondBrainWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        LockScreenWidget()
        QuickCaptureControl()
        FloorWalkControl()
        WalkNotesControl()
        ShiftLiveActivity()
    }
}

// MARK: - Home Screen widget (small / medium / large)

struct TodayWidget: Widget {
    let kind = "SecondBrainToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SecondBrainTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) { Theme.background }
        }
        .configurationDisplayName("Today")
        .description("Your most important task, priorities, reminders and follow-ups.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        if AppGroup.defaults.bool(forKey: SettingsKey.offDuty) {
            OffDutyView()
        } else {
            switch family {
            case .systemSmall: SmallView(entry: entry)
            case .systemMedium: MediumView(entry: entry)
            default: LargeView(entry: entry)
            }
        }
    }
}

/// Shown while an "Off duty" Focus filter is on.
private struct OffDutyView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.stars.fill").font(.title2).foregroundStyle(Theme.accent)
            Text("Off duty").font(.headline)
            Text("Work can wait.").font(.caption).foregroundStyle(.secondary)
        }
        .widgetURL(DeepLink.home)
    }
}

private struct SmallView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TODAY").font(.caption2.weight(.heavy)).foregroundStyle(Theme.accent)
                Spacer()
                if entry.overdueCount > 0 {
                    Text("\(entry.overdueCount) late").font(.caption2.weight(.bold)).foregroundStyle(Theme.danger)
                }
            }
            if let primary = entry.primary {
                Text(primary.title)
                    .font(.headline)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                if !primary.subtitle.isEmpty {
                    Text(primary.subtitle).font(.caption2).foregroundStyle(primary.isOverdue ? Theme.danger : .secondary)
                }
            } else {
                Text("All clear").font(.headline)
                Text("Tap to capture").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(entry.openCount) open · \(entry.dueTodayCount) due")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .widgetURL(entry.primary.map { DeepLink.task($0.id) } ?? DeepLink.capture)
    }
}

private struct MediumView: View {
    let entry: WidgetEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("PRIORITIES").font(.caption2.weight(.heavy)).foregroundStyle(Theme.accent)
                if entry.top.isEmpty {
                    Text("Nothing pressing. Nice.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(entry.top.prefix(3)) { item in
                    WidgetTaskRow(item: item)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                if let title = entry.nextReminderTitle, let date = entry.nextReminderDate {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(date.formatted(date: .omitted, time: .shortened), systemImage: "bell.fill")
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        Text(title).font(.caption).lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
                CountLine(value: entry.overdueCount, label: "overdue", tint: Theme.danger)
                CountLine(value: entry.dueTodayCount, label: "due today", tint: Theme.accent)
                Link(destination: DeepLink.capture) {
                    Label("Capture", systemImage: "plus.circle.fill").font(.caption.weight(.semibold))
                }
            }
            .frame(width: 104, alignment: .leading)
        }
        .widgetURL(DeepLink.home)
    }
}

private struct LargeView: View {
    let entry: WidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(entry.overdueCount) overdue · \(entry.dueTodayCount) due · \(entry.openCount) open")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            if entry.top.isEmpty {
                Text("All clear for today.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(entry.top.prefix(5)) { item in WidgetTaskRow(item: item) }

            Divider()
            HStack(spacing: 6) {
                ForEach(Quadrant.allCases) { q in
                    VStack(spacing: 1) {
                        Text("\(entry.quadrantCounts[q] ?? 0)").font(.headline.monospacedDigit()).foregroundStyle(Theme.color(for: q))
                        Text(q.code).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Theme.color(for: q).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .widgetURL(DeepLink.matrix)

            if !entry.followUps.isEmpty {
                Text("FOLLOW-UPS").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
                ForEach(entry.followUps.prefix(3)) { item in
                    Link(destination: DeepLink.task(item.id)) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.clock").foregroundStyle(Theme.accent)
                            Text(item.title).font(.caption).lineLimit(1)
                            Spacer()
                            Text(item.subtitle).font(.caption2).foregroundStyle(item.isOverdue ? Theme.danger : .secondary).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A row with an interactive checkbox that completes the task without opening the app.
private struct WidgetTaskRow: View {
    let item: WidgetEntry.Item

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: item.id)) {
                Image(systemName: "circle")
                    .font(.body)
                    .foregroundStyle(Theme.color(for: item.quadrant))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(item.title)")
            Link(destination: DeepLink.task(item.id)) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).font(.caption2).foregroundStyle(item.isOverdue ? Theme.danger : .secondary).lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct CountLine: View {
    let value: Int
    let label: String
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(value > 0 ? tint : .secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Lock Screen widgets

struct LockScreenWidget: Widget {
    let kind = "SecondBrainLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SecondBrainTimelineProvider()) { entry in
            LockScreenWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Glance")
        .description("Next reminder, priority count, or today's primary responsibility.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    var body: some View {
        if AppGroup.defaults.bool(forKey: SettingsKey.offDuty) {
            Label("Off duty", systemImage: "moon.stars.fill")
                .widgetURL(DeepLink.home)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").font(.caption)
                    Text("\(entry.priorityCount)").font(.title3.weight(.bold).monospacedDigit())
                }
            }
            .widgetAccentable()
            .accessibilityLabel("\(entry.priorityCount) priorities need attention")
            .widgetURL(DeepLink.home)
        case .accessoryInline:
            if let date = entry.nextReminderDate, let title = entry.nextReminderTitle {
                Label("\(date.formatted(date: .omitted, time: .shortened)) \(title)", systemImage: "bell.fill")
            } else {
                Label("\(entry.priorityCount) priorities · \(entry.dueTodayCount) due", systemImage: "brain.head.profile")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                if let date = entry.nextReminderDate, let title = entry.nextReminderTitle {
                    Label("Next · \(date.formatted(date: .omitted, time: .shortened))", systemImage: "bell.fill")
                        .font(.caption.weight(.bold))
                        .widgetAccentable()
                    Text(title).font(.headline).lineLimit(2)
                } else if let primary = entry.primary {
                    Label("Today", systemImage: "star.fill").font(.caption.weight(.bold)).widgetAccentable()
                    Text(primary.title).font(.headline).lineLimit(2)
                } else {
                    Label("Second Brain", systemImage: "brain.head.profile").font(.caption.weight(.bold)).widgetAccentable()
                    Text("All clear").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(entry.primary.map { DeepLink.task($0.id) } ?? DeepLink.home)
        }
    }
}

// MARK: - Control Center / Lock Screen / Action button control (iOS 18)

struct QuickCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SecondBrainQuickCapture") {
            ControlWidgetButton(action: OpenQuickCaptureIntent()) {
                Label("Quick Capture", systemImage: "bolt.fill")
            }
        }
        .displayName("Quick Capture")
        .description("Open Second Brain ready to capture.")
    }
}

struct FloorWalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SecondBrainFloorWalk") {
            ControlWidgetButton(action: OpenFloorWalkIntent()) {
                Label("Floor Walk", systemImage: "figure.walk")
            }
        }
        .displayName("Floor Walk")
        .description("Start a floor walk of your areas.")
    }
}

struct WalkNotesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SecondBrainWalkNotes") {
            ControlWidgetButton(action: OpenWalkNotesIntent()) {
                Label("Walk Notes", systemImage: "mic.fill")
            }
        }
        .displayName("Walk Notes")
        .description("Talk through what you see; each sentence becomes an item.")
    }
}
