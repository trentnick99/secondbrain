import Foundation
import SwiftData
import SecondBrainCore

/// Fictional sample data for exploring the app (and for UI tests). Names and situations are invented.
@MainActor
enum SampleData {
    static func load(into context: ModelContext, now: Date = Date()) {
        let cal = Calendar.current
        let math = DateMath(calendar: cal)
        let today = math.startOfDay(now)
        func day(_ offset: Int) -> Date { math.addingDays(offset, to: today) }
        func at(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date { math.date(on: day(offset), minutes: hour * 60 + minute) }

        // A fictional store team: store manager, coaches, team leads and associates.
        let morgan = Associate(name: "Morgan Hayes", department: "", role: "Store Manager")
        let chris = Associate(name: "Chris Patel", department: "Fresh", role: "Coach")
        let sam = Associate(name: "Sam Ortiz", department: "Overnight", role: "Coach")
        let jordan = Associate(name: "Jordan Ellis", department: "Stocking", role: "Team Lead")
        let marcus = Associate(name: "Marcus Lee", department: "Stocking", role: "Team Lead")
        let avery = Associate(name: "Avery Brooks", department: "Fresh", role: "Team Lead")
        let tasha = Associate(name: "Tasha Green", department: "Stocking", role: "Stocker")
        let priya = Associate(name: "Priya Shah", department: "Front End", role: "Cashier")
        for person in [morgan, chris, sam, jordan, marcus, avery, tasha, priya] { context.insert(person) }

        func task(_ title: String, kind: TaskKind = .task, quadrant: Quadrant, category: TaskCategory,
                  priority: TaskPriority = .normal, due: Date? = nil, hasTime: Bool = false, reminder: Date? = nil,
                  person: Associate? = nil, request: String = "", commitment: String = "",
                  status: TaskStatus = .notStarted) -> TaskItem {
            let t = TaskItem(title: title, kind: kind, status: status)
            t.quadrant = quadrant
            t.category = category
            t.priority = priority
            t.dueDate = due
            t.hasDueTime = hasTime && due != nil
            t.reminderDate = reminder.flatMap { $0 > now ? $0 : nil }
            t.request = request
            t.commitment = commitment
            if kind == .followUp { t.conversationDate = day(-1) }
            context.insert(t)
            t.associate = person
            if let person { t.department = person.department }
            let classification = TaskActions.classification(for: t, now: now)
            t.classificationReasons = classification.reasons.joined(separator: "\n")
            TaskActions.log(.created, "Sample data", task: t, in: context, date: now)
            return t
        }

        let spill = task("Wet floor by the dairy cooler — confirm cleanup and signage", kind: .issue, quadrant: .doFirst,
                         category: .safety, priority: .critical, due: today)
        spill.department = "Dairy"
        _ = task("Cover two open front-end shifts for Saturday", quadrant: .doFirst, category: .people, priority: .high,
                 due: at(0, 14), hasTime: true, reminder: at(0, 13, 30))
        _ = task("Check with Priya about her availability next week", kind: .followUp, quadrant: .schedule,
                 category: .people, due: day(1), reminder: at(1, 9), person: priya,
                 request: "Priya asked to adjust her availability", commitment: "Review the schedule and get back to her")
        _ = task("Help Jordan understand his new schedule", kind: .followUp, quadrant: .doFirst, category: .people,
                 due: today, reminder: at(0, 11), person: jordan, request: "Jordan is confused by the new rotation",
                 commitment: "Walk through it with him before lunch")
        _ = task("Talk to the overnight coach about the freight backlog", kind: .followUp, quadrant: .schedule,
                 category: .freight, due: day(1), person: sam)
        _ = task("Prep notes for the district visit", quadrant: .schedule, category: .meeting, priority: .high, due: day(3))
        _ = task("Build a cross-training plan for Marcus", quadrant: .schedule, category: .development, due: day(5), person: marcus)
        _ = task("Review last week's results with the team", quadrant: .schedule, category: .admin, due: day(2))
        _ = task("Reprint missing shelf labels in aisle 12", quadrant: .delegate, category: .merchandising, due: today)
        let delegated = task("Routine price-change audit", quadrant: .delegate, category: .merchandising, due: day(1), person: avery)
        delegated.delegatedTo = "Avery Brooks"
        delegated.waitingOn = "Avery Brooks"
        delegated.status = .waiting
        let steel = task("Work the steel in aisle 9", quadrant: .doFirst, category: .freight, due: today, person: marcus)
        steel.delegatedTo = "Marcus Lee"
        steel.waitingOn = "Marcus Lee"
        steel.status = .waiting
        _ = task("Freight plan for the store manager", quadrant: .schedule, category: .freight, priority: .high,
                 due: day(2), person: morgan)
        _ = task("Train Tasha on the pallet jack", quadrant: .schedule, category: .development, due: day(4), person: tasha)
        _ = task("Reorganize the old training binder", quadrant: .eliminate, category: .admin, priority: .low)
        let overdue = task("Submit the cooler repair request", quadrant: .doFirst, category: .operations, due: day(-1))
        overdue.rescheduleCount = 3
        let done = task("Morning safety walk", quadrant: .schedule, category: .safety, due: today)
        done.status = .completed
        done.completedAt = at(0, 7, 30) < now ? at(0, 7, 30) : now
        _ = task("Ask about extra pallet jacks for receiving", quadrant: .schedule, category: .freight, status: .inbox)

        let rule = RecurrenceRule.weekly(on: [2])
        let series = RecurrenceSeries(title: "Review safety observations", rule: rule, anchorDate: today)
        series.category = .safety
        series.isImportant = true
        series.hasTime = true
        series.timeMinutes = 8 * 60
        context.insert(series)

        let daily = RecurrenceSeries(title: "Walk the sales floor", rule: .weekdaysOnly, anchorDate: today)
        daily.category = .operations
        daily.hasTime = true
        daily.timeMinutes = 9 * 60
        context.insert(daily)

        let note = Note(title: "Weekly huddle", body: """
        Grocery in-stock improved this week.
        I'll get back to Priya about her availability request Friday.
        Need to check the backroom capacity tomorrow.
        """, type: .meeting)
        note.tags = ["huddle", "weekly"]
        note.isPinned = true
        context.insert(note)
        let item = ChecklistItem(text: "Share recognition shout-outs", sortIndex: 0)
        context.insert(item)
        item.note = note

        let idea = Note(title: "Idea: move seasonal endcap closer to the entrance", body: "Could help sell-through before the holiday rush.", type: .idea)
        context.insert(idea)

        TaskActions.logInteraction(.conversation, "Discussed weekend coverage", associate: priya, in: context, date: day(-2))
        TaskActions.logInteraction(.request, "Asked for help with the new schedule", associate: jordan, in: context, date: day(-1))

        RecurrenceService.materialize(in: context, now: now, saving: false)
        TaskActions.save(context)
    }
}
