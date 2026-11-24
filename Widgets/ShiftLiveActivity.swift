import ActivityKit
import SwiftUI
import WidgetKit

/// The shift on the Lock Screen and in the Dynamic Island.
struct ShiftLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShiftActivityAttributes.self) { context in
            ShiftLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Theme.heroFill)
                .activitySystemActionForegroundColor(Theme.heroText)
                .widgetURL(URL(string: "secondbrain://home"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.done)/\(context.state.total)", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.heroProgress)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimeLeftText(attributes: context.attributes)
                        .font(.headline)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PriorityList(priorities: context.state.priorities, compact: true)
                }
            } compactLeading: {
                Label("\(context.state.done)/\(context.state.total)", systemImage: "checklist")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.heroProgress)
            } compactTrailing: {
                TimeLeftText(attributes: context.attributes)
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "checklist").foregroundStyle(Theme.heroProgress)
            }
            .widgetURL(URL(string: "secondbrain://home"))
        }
    }
}

private struct ShiftLockScreenView: View {
    let attributes: ShiftActivityAttributes
    let state: ShiftActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(attributes.shiftLabel, systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.heroSecondary)
                Spacer()
                TimeLeftText(attributes: attributes)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.heroText)
                    .multilineTextAlignment(.trailing)
            }
            ProgressView(value: Double(state.done), total: Double(max(state.total, 1)))
                .tint(Theme.heroProgress)
            HStack {
                Text(state.total == 0 ? "Nothing due today" : "\(state.done) of \(state.total) done")
                if state.overdue > 0 {
                    Text("· \(state.overdue) overdue").foregroundStyle(Color(red: 1, green: 0.62, blue: 0.62))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.heroSecondary)
            PriorityList(priorities: state.priorities, compact: false)
        }
        .padding(16)
    }
}

/// Counts down to the end of the shift without needing updates.
private struct TimeLeftText: View {
    let attributes: ShiftActivityAttributes

    var body: some View {
        Text(timerInterval: attributes.start...max(attributes.end, attributes.start), countsDown: true)
            .monospacedDigit()
    }
}

private struct PriorityList: View {
    let priorities: [String]
    let compact: Bool

    var body: some View {
        if priorities.isEmpty {
            Text("No priorities open. Nice work.")
                .font(.caption)
                .foregroundStyle(Theme.heroSecondary)
        } else {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                ForEach(Array(priorities.enumerated()), id: \.offset) { index, title in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.heroProgress)
                        Text(title)
                            .font(compact ? .caption : .subheadline)
                            .foregroundStyle(Theme.heroText)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
