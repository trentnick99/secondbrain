import SwiftData
import XCTest
@testable import SecondBrain

/// Integration tests for the SwiftData layer, using an isolated in-memory store.
@MainActor
final class PersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        container = PersistenceController.makeInMemory()
        context = ModelContext(container)
        DataChange.handlers = []
    }

    override func tearDown() async throws {
        context = nil
        container = nil
    }

    private func draft(_ text: String, known: [String] = []) -> CaptureDraft {
        let parsed = NaturalLanguageParser().parse(text, context: AppSettings.captureContext(knownAssociates: known))
        return CaptureDraft(parsed: parsed)
    }

    // MARK: Quick note (Action button)

    func testQuickNoteSavesExactlyWhatWasSaid() throws {
        let reply = QuickNoteSaver.save("  Check the dairy cooler temp log\nand call maintenance  ", in: context)
        XCTAssertEqual(reply, "Saved to Notes.")
        let notes = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Check the dairy cooler temp log")
        XCTAssertEqual(notes[0].body, "Check the dairy cooler temp log\nand call maintenance")
        XCTAssertEqual(notes[0].tagsRaw, QuickNoteSaver.tag)
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty, "A quick note never becomes a task on its own")
        XCTAssertEqual(QuickNoteSaver.save("   ", in: context), "I didn't catch a note.")
        XCTAssertTrue(QuickNoteSaver.save("Sam's write up is Friday", in: context).contains("Heads up"))
    }

    // MARK: Lock Screen shift

    func testShiftActivityShowsTheTopThreeOpenPriorities() throws {
        let today = Date()
        for (index, title) in ["Clear the fire exits", "Cover open SCO shifts", "Submit the cooler request", "Zone aisle 9"].enumerated() {
            let task = TaskItem(title: title)
            task.dueDate = today
            task.quadrant = index < 3 ? .doFirst : .schedule
            context.insert(task)
        }
        let done = TaskItem(title: "Huddle")
        done.dueDate = today
        context.insert(done)
        try context.save()
        _ = TaskActions.complete(done, in: context)
        let state = ShiftActivityController.state(in: context, now: today)
        XCTAssertEqual(state.priorities.count, 3)
        XCTAssertFalse(state.priorities.contains("Huddle"), "Done work isn't a priority")
        XCTAssertEqual(state.done, 1)
        XCTAssertGreaterThanOrEqual(state.total, 5)
    }

    // MARK: Importing notes

    func testImportedItemsSaveWithTheirAreaAndOnlyStatedDates() throws {
        let notes = """
        Total store:
        - Clear all fire exits by Friday
        Food
        - Rotate the bread aisle
        Fresh:
        - Cull the wet wall
        """
        let result = NoteImporter.parse(notes, role: UserRole(role: .coach, areas: ["Food"]),
                                        context: AppSettings.captureContext(knownAssociates: []))
        let chosen = result.items.filter { $0.relevance == .mine || $0.relevance == .totalStore }
        XCTAssertEqual(chosen.count, 2, "The Fresh item is left out for a Food coach")
        for item in chosen { _ = CaptureSaver.save(CaptureDraft(parsed: item.parsed), in: context) }
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(Set(tasks.map(\.department)), ["Total Store", "Food"])
        XCTAssertNotNil(tasks.first { $0.department == "Total Store" }?.dueDate)
        XCTAssertNil(tasks.first { $0.department == "Food" }?.dueDate, "No date is invented")
        XCTAssertTrue(MyAreaCard.belongs(tasks[0], to: UserRole(role: .coach, areas: ["Food"])))
    }

    // MARK: Season Planner

    func testSeasonPrepStepBecomesATaskOnlyWhenAdded() throws {
        let christmas = RetailCalendar.moments(inYear: 2026, calendar: .current).first { $0.title == "Christmas" }!
        let step = christmas.prep[0]
        XCTAssertTrue(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty, "Nothing is created until Add is tapped")
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10))!
        let task = try XCTUnwrap(SeasonPlanActions.addTask(for: step, in: christmas, context: context, now: now))
        XCTAssertEqual(task.title, step.title)
        XCTAssertEqual(task.category, step.category)
        XCTAssertNotNil(task.dueDate)
        XCTAssertLessThan(task.dueDate!, christmas.start)
        XCTAssertTrue(task.details.contains("Season Planner"))
        XCTAssertTrue(SeasonPlanStore.addedKeys.contains(step.key))
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).count, 1)
    }

    // MARK: Quick Capture → persistence

    func testCaptureCreatesFollowUpAndAssociate() throws {
        let result = CaptureSaver.save(draft("Check with John tomorrow about his schedule."), in: context)
        guard case .task(let task)? = result else { return XCTFail("Expected a task") }
        XCTAssertEqual(task.kind, .followUp)
        XCTAssertEqual(task.associate?.name, "John")
        XCTAssertNotNil(task.dueDate)
        XCTAssertEqual(task.request, task.title)
        let people = try context.fetch(FetchDescriptor<Associate>())
        XCTAssertEqual(people.count, 1)
        XCTAssertFalse(people[0].history.isEmpty, "The request is logged in interaction history")
    }

    func testCaptureReusesExistingAssociate() throws {
        let sarah = Associate(name: "Sarah Kim")
        context.insert(sarah)
        try context.save()
        _ = CaptureSaver.save(draft("Follow up with Sarah about availability", known: ["Sarah Kim"]), in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Associate>()).count, 1)
        XCTAssertEqual(sarah.openFollowUps.count, 1)
    }

    func testInboxSaveKeepsRawTextAndInventsNothing() throws {
        let task = try XCTUnwrap(CaptureSaver.saveToInbox("talk to someone about the thing next week", in: context))
        XCTAssertEqual(task.status, .inbox)
        XCTAssertEqual(task.title, "talk to someone about the thing next week")
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.reminderDate)
        XCTAssertNil(task.associate)
    }

    func testNoteCaptureCreatesNote() throws {
        let result = CaptureSaver.save(draft("Idea: move seasonal closer to the entrance"), in: context)
        guard case .note(let note)? = result else { return XCTFail("Expected a note") }
        XCTAssertEqual(note.type, .idea)
    }

    func testRecurringCaptureCreatesSeriesAndOccurrences() throws {
        let result = CaptureSaver.save(draft("Remind me every day to walk the sales floor"), in: context)
        guard case .series(let series)? = result else { return XCTFail("Expected a series") }
        let occurrences = RecurrenceService.occurrences(of: series, in: context)
        XCTAssertGreaterThanOrEqual(occurrences.count, 7, "A week of daily occurrences is materialized ahead")
        // Running again creates no duplicates.
        RecurrenceService.materialize(in: context)
        XCTAssertEqual(RecurrenceService.occurrences(of: series, in: context).count, occurrences.count)
        XCTAssertEqual(Set(occurrences.map(\.occurrenceKey)).count, occurrences.count)
    }

    func testDeletedOccurrenceIsNotRecreated() throws {
        let series = RecurrenceService.createSeries(title: "Cooler temps", details: "", rule: .daily, anchor: Date(), timeMinutes: nil,
                                                    kind: .task, category: .compliance, priority: .normal, quadrant: nil,
                                                    associate: nil, department: "", in: context)
        let first = try XCTUnwrap(RecurrenceService.occurrences(of: series, in: context).last)
        let key = first.occurrenceKey
        TaskActions.delete(first, in: context)
        RecurrenceService.materialize(in: context)
        XCTAssertFalse(RecurrenceService.occurrences(of: series, in: context).contains { $0.occurrenceKey == key })
    }

    func testPausingRemovesOnlyFutureUntouchedOccurrences() throws {
        let series = RecurrenceService.createSeries(title: "Walk", details: "", rule: .daily, anchor: Date(), timeMinutes: nil,
                                                    kind: .task, category: .operations, priority: .normal, quadrant: nil,
                                                    associate: nil, department: "", in: context)
        RecurrenceService.pause(series, in: context)
        let remaining = RecurrenceService.occurrences(of: series, in: context)
        XCTAssertEqual(remaining.count, 1, "Today's occurrence stays; future untouched ones are removed")
    }

    // MARK: Task lifecycle

    func testCompleteReopenAndHistory() throws {
        let task = TaskActions.createTask(title: "Fix the baler sign", in: context)
        XCTAssertTrue(TaskActions.complete(task, notes: "Replaced", in: context))
        XCTAssertEqual(task.status, .completed)
        XCTAssertNotNil(task.completedAt)
        XCTAssertEqual(task.completionNotes, "Replaced")
        TaskActions.reopen(task, in: context)
        XCTAssertEqual(task.status, .notStarted)
        XCTAssertNil(task.completedAt)
        let kinds = task.sortedActivity.map(\.kindRaw)
        XCTAssertTrue(kinds.contains(ActivityKind.completed.rawValue))
        XCTAssertTrue(kinds.contains(ActivityKind.reopened.rawValue))
    }

    func testRescheduleCountsPostponements() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let task = TaskActions.createTask(title: "Submit repair request", due: today, in: context)
        TaskActions.reschedule(task, to: cal.date(byAdding: .day, value: 2, to: today)!, in: context)
        TaskActions.reschedule(task, to: cal.date(byAdding: .day, value: 3, to: today)!, in: context)
        XCTAssertEqual(task.rescheduleCount, 2)
    }

    func testCarryForwardMovesUnfinishedToTomorrowAndKeepsThem() throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let a = TaskActions.createTask(title: "A", due: today, in: context)
        let b = TaskActions.createTask(title: "B", due: cal.date(byAdding: .day, value: -1, to: today), in: context)
        let done = TaskActions.createTask(title: "Done", due: today, in: context)
        _ = TaskActions.complete(done, in: context)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        TaskActions.carryForward([a, b, done], to: tomorrow, in: context)
        XCTAssertTrue(cal.isDate(a.dueDate!, inSameDayAs: tomorrow))
        XCTAssertTrue(cal.isDate(b.dueDate!, inSameDayAs: tomorrow))
        XCTAssertTrue(cal.isDate(done.dueDate!, inSameDayAs: today), "Completed work is not moved")
        XCTAssertEqual(try context.fetch(FetchDescriptor<TaskItem>()).count, 3, "Nothing is discarded")
    }

    func testManualQuadrantOverrideSticksAndIsLogged() throws {
        let task = TaskActions.createTask(title: "Reprint labels", due: Date(), in: context)
        TaskActions.setQuadrant(task, .schedule, in: context)
        XCTAssertTrue(task.classificationIsManual)
        XCTAssertEqual(task.quadrant, .schedule)
        TaskActions.reclassifyIfAutomatic(task)
        XCTAssertEqual(task.quadrant, .schedule, "Automatic reclassification never overrides a manual choice")
        XCTAssertTrue(task.sortedActivity.contains { $0.kindRaw == ActivityKind.quadrantChanged.rawValue })
    }

    func testDelegationIsNeverAssumedAccepted() throws {
        let task = TaskActions.createTask(title: "Price change audit", in: context)
        TaskActions.delegate(task, to: "Avery", in: context)
        XCTAssertEqual(task.status, .waiting)
        XCTAssertFalse(task.delegationConfirmed)
        XCTAssertTrue(task.isAwaitingConfirmation)
        TaskActions.confirmDelegation(task, in: context)
        XCTAssertTrue(task.delegationConfirmed)
    }

    func testCapturedHandOffWaitsForConfirmation() throws {
        let lead = Associate(name: "Jordan Ellis", department: "Stocking", role: "Team Lead")
        context.insert(lead)
        try context.save()
        let result = CaptureSaver.save(draft("Have Jordan work the truck by end of shift", known: ["Jordan Ellis"]), in: context)
        guard case .task(let task)? = result else { return XCTFail("Expected a task") }
        XCTAssertEqual(task.delegatedTo, "Jordan Ellis")
        XCTAssertEqual(task.status, .waiting)
        XCTAssertFalse(task.delegationConfirmed, "A hand-off is never assumed accepted")
        XCTAssertEqual(task.associate?.name, "Jordan Ellis")
        XCTAssertEqual(lead.storeRole, .teamLead)
        XCTAssertTrue(task.sortedActivity.contains { $0.kindRaw == ActivityKind.delegated.rawValue })
    }

    func testGroupRolesDoNotBecomeAssociates() throws {
        _ = CaptureSaver.save(draft("Tell my TLs to work the truck at 2pm"), in: context)
        _ = CaptureSaver.save(draft("Ask the stocking TLs to condense the bins"), in: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<Associate>()).isEmpty)
    }

    func testHandOffToATeamWaitsWithoutCreatingAContact() throws {
        let result = CaptureSaver.save(draft("Have Stock 2 work the remix tonight"), in: context)
        guard case .task(let task)? = result else { return XCTFail("Expected a task") }
        XCTAssertEqual(task.delegatedTo, "Stock 2")
        XCTAssertEqual(task.status, .waiting)
        XCTAssertFalse(task.delegationConfirmed)
        XCTAssertEqual(task.department, "Stocking")
        XCTAssertTrue(try context.fetch(FetchDescriptor<Associate>()).isEmpty)
    }

    func testTopThreeLimit() throws {
        let tasks = (1...4).map { TaskActions.createTask(title: "T\($0)", in: context) }
        XCTAssertTrue(TaskActions.toggleFocus(tasks[0], in: context))
        XCTAssertTrue(TaskActions.toggleFocus(tasks[1], in: context))
        XCTAssertTrue(TaskActions.toggleFocus(tasks[2], in: context))
        XCTAssertFalse(TaskActions.toggleFocus(tasks[3], in: context), "Only three main priorities per day")
    }

    func testChecklistItemConvertsToTask() throws {
        let note = Note(title: "Huddle", body: "")
        context.insert(note)
        let item = ChecklistItem(text: "Order pallet jacks")
        context.insert(item)
        item.note = note
        let task = TaskActions.convert(item, in: context)
        XCTAssertEqual(task.title, "Order pallet jacks")
        XCTAssertEqual(item.convertedTaskID, task.id)
        XCTAssertTrue((note.linkedTasks ?? []).contains { $0.id == task.id })
    }

    func testSnoozeSetsReminder() throws {
        let task = TaskActions.createTask(title: "Call vendor", in: context)
        let before = Date()
        TaskActions.snooze(task, option: .fifteenMinutes, in: context)
        let reminder = try XCTUnwrap(task.reminderDate)
        XCTAssertGreaterThan(reminder, before.addingTimeInterval(14 * 60))
    }

    // MARK: Backup

    func testBackupRoundTrip() throws {
        _ = CaptureSaver.save(draft("Check with John tomorrow about his schedule."), in: context)
        _ = CaptureSaver.save(draft("Idea: new endcap"), in: context)
        _ = RecurrenceService.createSeries(title: "Walk", details: "", rule: .weekdaysOnly, anchor: Date(), timeMinutes: 540,
                                           kind: .task, category: .operations, priority: .normal, quadrant: nil,
                                           associate: nil, department: "", in: context)
        let data = try BackupService.makeBackup(from: context)
        let taskCount = try context.fetch(FetchDescriptor<TaskItem>()).count

        let otherContainer = PersistenceController.makeInMemory()
        let other = ModelContext(otherContainer)
        let summary = try BackupService.restore(data, into: other)
        XCTAssertGreaterThan(summary.inserted, 0)
        XCTAssertEqual(try other.fetch(FetchDescriptor<TaskItem>()).count, taskCount)
        XCTAssertEqual(try other.fetch(FetchDescriptor<Associate>()).first?.name, "John")
        XCTAssertEqual(try other.fetch(FetchDescriptor<Note>()).count, 1)
        XCTAssertEqual(try other.fetch(FetchDescriptor<RecurrenceSeries>()).count, 1)
        let restoredFollowUp = try other.fetch(FetchDescriptor<TaskItem>()).first { $0.kind == .followUp }
        XCTAssertEqual(restoredFollowUp?.associate?.name, "John", "Relationships are restored")

        // Restoring the same file again changes nothing.
        let again = try BackupService.restore(data, into: other)
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(try other.fetch(FetchDescriptor<TaskItem>()).count, taskCount)
    }

    // MARK: Notifications plan from real models

    func testNotificationPlanFromModels() throws {
        let task = TaskActions.createTask(title: "Call electrician", due: Date().addingTimeInterval(7200), hasTime: true,
                                          reminder: Date().addingTimeInterval(3600), in: context)
        let plan = NotificationPlanner.plan(tasks: [task.snapshot], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                            now: Date(), calendar: .current)
        XCTAssertEqual(plan.first?.kind, .reminder)
        XCTAssertEqual(plan.first?.taskID, task.id)
        TaskActions.complete(task, in: context)
        let after = NotificationPlanner.plan(tasks: [task.snapshot], preferences: NotificationPreferences(dailyBriefingEnabled: false),
                                             now: Date(), calendar: .current)
        XCTAssertTrue(after.isEmpty, "Completing a task cancels its notifications on the next resync")
    }
}
