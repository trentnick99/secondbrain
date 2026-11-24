import SwiftData
import SwiftUI
import SecondBrainCore

/// A compact, one-hand-friendly task row with a large completion target.
struct TaskRowView: View {
    let task: TaskItem
    var showQuadrant: Bool = true
    var showAssociate: Bool = true
    @Environment(\.modelContext) private var context

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CompletionButton(task: task)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if task.kind != .task {
                        Image(systemName: task.kind.systemImage)
                            .font(.caption)
                            .foregroundStyle(task.kind == .issue ? Theme.warning : Theme.accent)
                            .accessibilityHidden(true)
                    }
                    Text(task.displayTitle)
                        .font(.body)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                }
                metaLine
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                if showQuadrant && task.isOpen && task.status != .inbox {
                    QuadrantBadge(quadrant: task.quadrant, compact: true)
                }
                if task.priority == .critical || task.priority == .high {
                    Image(systemName: "flag.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.color(for: task.priority))
                        .accessibilityLabel("\(task.priority.title) priority")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var metaLine: some View {
        let items = metaItems
        if !items.isEmpty {
            // One line when it fits; otherwise each detail on its own line instead of truncating them all.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.text) { metaLabel($0) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.text) { metaLabel($0) }
                }
            }
        }
    }

    private func metaLabel(_ item: Meta) -> some View {
        Label(item.text, systemImage: item.icon)
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .foregroundStyle(item.color)
            .lineLimit(1)
    }

    private struct Meta { let text: String; let icon: String; let color: Color }

    private var metaItems: [Meta] {
        var items: [Meta] = []
        let now = Date()
        if let due = task.dueDate, task.isOpen {
            let overdue = task.isOverdue(now: now)
            items.append(Meta(text: RelativeDateText.dueText(due: due, hasTime: task.hasDueTime, now: now, calendar: .current),
                              icon: overdue ? "exclamationmark.circle" : "calendar",
                              color: overdue ? Theme.danger : .secondary))
        } else if let done = task.completedAt, task.isCompleted {
            items.append(Meta(text: "Done \(RelativeDateText.timeText(done, calendar: .current))", icon: "checkmark", color: .secondary))
        }
        if showAssociate, let name = task.associate?.name {
            items.append(Meta(text: name, icon: "person", color: .secondary))
        }
        if task.isAwaitingConfirmation {
            items.append(Meta(text: task.delegatedTo.isEmpty ? "Waiting" : "Waiting on \(task.delegatedTo)", icon: "hourglass", color: Theme.warning))
        }
        if task.isRecurring {
            items.append(Meta(text: "Repeats", icon: "repeat", color: .secondary))
        }
        if let reminder = task.reminderDate, task.isOpen, reminder > now, task.dueDate == nil {
            items.append(Meta(text: RelativeDateText.dueText(due: reminder, hasTime: true, now: now, calendar: .current), icon: "bell", color: .secondary))
        }
        return items
    }
}

struct CompletionButton: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context

    var body: some View {
        Button {
            if task.isCompleted {
                TaskActions.reopen(task, in: context)
            } else {
                withAnimation(.snappy) { _ = TaskActions.complete(task, in: context) }
            }
        } label: {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(task.isCompleted ? Theme.success : Theme.color(for: task.quadrant).opacity(task.isOpen ? 0.9 : 0.4))
                .frame(width: 44, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: task.isCompleted)
        .accessibilityLabel(task.isCompleted ? "Mark not done" : "Mark complete")
    }
}

struct QuadrantBadge: View {
    let quadrant: Quadrant
    var compact: Bool = false

    var body: some View {
        Text(compact ? quadrant.code : "\(quadrant.code) · \(quadrant.title)")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(Theme.color(for: quadrant))
            .background(Theme.color(for: quadrant).opacity(0.15), in: Capsule())
            .accessibilityLabel("\(quadrant.code), \(quadrant.title)")
    }
}
