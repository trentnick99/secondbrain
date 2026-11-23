import SwiftUI
import SecondBrainCore

/// Section header for card-style screens.
struct SectionTitle: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(tint).accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            if let count {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A titled card listing tasks, with an empty message.
struct TaskCard: View {
    let title: String
    var systemImage: String
    var tint: Color = Theme.accent
    let tasks: [TaskItem]
    var emptyText: String? = nil
    var limit: Int = 6
    var showQuadrant: Bool = true
    @Environment(AppRouter.self) private var router

    var body: some View {
        if !tasks.isEmpty || emptyText != nil {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: title, systemImage: systemImage, count: tasks.isEmpty ? nil : tasks.count, tint: tint)
                if tasks.isEmpty, let emptyText {
                    Text(emptyText).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 4)
                } else {
                    ForEach(tasks.prefix(limit)) { task in
                        Button { router.open(.task(task.id)) } label: {
                            TaskRowView(task: task, showQuadrant: showQuadrant)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { TaskQuickMenu(task: task) }
                        if task.id != tasks.prefix(limit).last?.id { Divider().padding(.leading, 56) }
                    }
                    if tasks.count > limit {
                        Text("+ \(tasks.count - limit) more").font(.footnote).foregroundStyle(.secondary).padding(.leading, 56)
                    }
                }
            }
            .card()
        }
    }
}

/// A smaller context menu usable outside of List rows.
struct TaskQuickMenu: View {
    let task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router

    var body: some View {
        if task.isOpen {
            Button { TaskActions.complete(task, in: context) } label: { Label("Complete", systemImage: "checkmark.circle") }
            Button {
                TaskActions.reschedule(task, to: Rescheduler.carryForwardDay(now: Date(), calendar: .current), in: context)
                router.showToast("Moved to tomorrow")
            } label: { Label("Move to Tomorrow", systemImage: "sunrise") }
            Menu {
                ForEach(SnoozeOption.allCases) { option in
                    Button(option.title) { TaskActions.snooze(task, option: option, in: context) }
                }
            } label: { Label("Snooze Reminder", systemImage: "bell.badge") }
            Button {
                if !TaskActions.toggleFocus(task, in: context) { router.showToast("You already have 3 priorities today") }
            } label: { Label("Toggle Top 3", systemImage: "star") }
        } else {
            Button { TaskActions.reopen(task, in: context) } label: { Label("Reopen", systemImage: "arrow.uturn.backward") }
        }
        Button { router.open(.task(task.id)) } label: { Label("Open", systemImage: "arrow.up.forward.square") }
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A tappable chip used in capture and filters.
struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var tint: Color = Theme.accent
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .background(isSelected ? tint : Theme.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Privacy reminder shown wherever people information is entered.
struct PrivacyReminder: View {
    var body: some View {
        Label {
            Text("Personal organizer only. Don't store medical details, disciplinary records, passwords or confidential personnel information.")
        } icon: {
            Image(systemName: "hand.raised")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// Picks one of the day's quick dates or none.
struct QuickDateChips: View {
    @Binding var date: Date?
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let options: [QuickDateOption] = [
            QuickDateOption(title: "None", date: nil),
            QuickDateOption(title: "Today", date: today),
            QuickDateOption(title: "Tomorrow", date: cal.date(byAdding: .day, value: 1, to: today)),
            QuickDateOption(title: "Next week", date: cal.date(byAdding: .day, value: 7, to: today))
        ]
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(options) { option in
                    Chip(title: option.title, isSelected: isSelected(option.date)) { date = option.date }
                }
            }
        }
    }

    struct QuickDateOption: Identifiable {
        let title: String
        let date: Date?
        var id: String { title }
    }

    private func isSelected(_ value: Date?) -> Bool {
        switch (date, value) {
        case (nil, nil): return true
        case let (a?, b?): return Calendar.current.isDate(a, inSameDayAs: b)
        default: return false
        }
    }
}
