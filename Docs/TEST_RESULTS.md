# Test results

## Cloud Mac (GitHub Actions) — 2026-11-25 (builds 13 and 15)

Runner `macos-26-intel` · **Xcode 26.6** · simulator **iPhone 17 Pro, iOS 26.5**. SwiftLint (`--strict`) passes on both.

| Suite | Build 13 (audit stages 1–4) | Build 15 (stage 5) |
|---|---|---|
| **Compile:** app, widget, Watch app, unit and UI test targets | ✅ run 45699962001 | ✅ run 45712885487 |
| **SecondBrainCoreTests** (engine) | ✅ 177 / 177 | ✅ 184 / 184 (adds season events, temperature limits, list sharing) |
| **SecondBrainTests** (SwiftData integration) | ✅ 30 / 30, including the schema frozen against the entity hashes of builds 1–12 and a store written by the old schema reopening with its data | ✅ 34 / 34, adding the V1 → V2 upgrade, check-offs and season events in backups, and Home loading a year of history (5,000 tasks) in under 0.5 s |
| **SecondBrainUITests** (end-to-end) | ✅ 17 / 17 (run 45711795502). The first run failed only the Huddle test, which checked for the share row without scrolling to it; the test now scrolls. | ✅ 19 / 19 (run 45712885487), adding your own season event and a reading outside the standard becoming a task. Two passed on the automatic retry: a simulator launch timeout, and a text field that hadn't taken focus yet (the test now taps it first). |
| **Screenshots** | ✅ 24 screens (run 45711800286) | ✅ 24 screens (run 45720125479), on the `screenshots` branch |
| **Signed release + TestFlight upload** | ✅ **Build 13 uploaded** (run 45711804343) | ✅ **Build 15 uploaded** (run 45724807791). The first try (run 45720129169, which would have been build 14) stalled in the archive step for over 30 minutes with no output and was cancelled; the retry archived in 8 minutes. Build numbers follow run numbers, so there's no build 14. The archive step now stops after 30 minutes and streams its progress. |
| **On-device checks** | ⏳ See the manual checklist below, plus: Home's greeting after midnight, Delete all data removing the Files backups, a widget checkbox clearing its reminder | ⏳ Plus: the database upgrade on a phone that has real data, a check-off saved and restored, the widget's next-shift arrow |

## Cloud Mac (GitHub Actions) — 2026-11-25 (Coach Spark, build 12)

Runner `macos-26-intel` · **Xcode 26.6** · simulator **iPhone 17 Pro, iOS 26.5**. Workflow: `.github/workflows/build.yml`.

| Suite | Result |
|---|---|
| **Compile:** app, widget extension, Apple Watch app, unit-test and UI-test targets (Debug, simulator) | ✅ **Succeeded** (run 45551404403) |
| **SecondBrainCoreTests**: 176 engine tests, including holidays, the fiscal week, Season Planner prep dates, store terms, team hand-offs, privacy notes, roles, importing notes, Standards (built-in temperatures match the FDA Food Code, 21 CFR 115.50 and USDA values; search filters lists; your own lists; old guides become process lists once), scanned text, walk notes, floor walks, shift handoffs, weather alerts, huddles, the shift timeline, team lead lists, weekly recaps and What's next | ✅ **176 / 176 passed** |
| **SecondBrainTests**: 24 SwiftData integration tests (in-memory store) | ✅ **Passed** (`TEST EXECUTE SUCCEEDED`, run 45551404403) |
| **SecondBrainUITests**: 16 end-to-end tests (in-memory store, fictional data) | ✅ **16 / 16 passed** (run 45556141257). The tests cover: Quick Capture, ambiguous captures, the privacy note, the Matrix, End My Shift, the weekly planner, Store Terms, the Season Planner, Import notes (from More tools), editing the schedule, notes on Home, Standards (food temperatures and sources, a process step to a task, your own temperature list), the floor walk, and the huddle. In the first run, 3 failed: one simulator launch timeout, Import notes sitting below the half-height More tools sheet (the sheet now opens full height), and a floor walk toast that disappeared before the slow simulator read it (the test now checks the task itself). The rerun passed all 16. The Apple Watch app, scan, speech, weather location and the Live Activity need real devices, so they're covered by compile checks and engine tests only. |
| **Screenshots** | ✅ 24 screens (run 45556193538), on the `screenshots` branch |
| **Signed release + TestFlight upload** | ✅ **Build 12 uploaded** (run 45559615273). Apple processes it before it shows in TestFlight. |
| **On-device checks**: notifications in each app state, widgets, Siri, Face ID, speech | ⏳ After installing from TestFlight. See the manual checklist below. |

## Linux build environment — 2026-11-25

| Check | Result |
|---|---|
| Engine tests (Swift 5.10.1, Linux) | ✅ 176 / 176 |
| `swiftc -parse` on all app, widget and test files | ✅ 66 files |
| Project validation (`scripts/validate_project.py`) | ✅ |

## Engine tests (passed)

All of these use a fixed clock (Monday 23 Nov 2026, 10:00 Central) so they're deterministic.

**CaptureParserTests** (25 passed)

- ✅ `testCheckResultsThursday` — Check results thursday
- ✅ `testCheckWithJohnTomorrow` — Check with john tomorrow
- ✅ `testCommonWordsAreNotNames` — Common words are not names
- ✅ `testDairyBeforeFriday` — Dairy before friday
- ✅ `testEmptyInput` — Empty input
- ✅ `testEndOfShift` — End of shift
- ✅ `testExplicitCalendarDate` — Explicit calendar date
- ✅ `testExplicitPrefixes` — Explicit prefixes
- ✅ `testExplicitTime` — Explicit time
- ✅ `testFollowUpWithSarahNextWeek` — Follow up with sarah next week
- ✅ `testInThreeDays` — In three days
- ✅ `testKnownAssociateIsNotFlagged` — Known associate is not flagged
- ✅ `testNoDateMeansNoDate` — No date means no date
- ✅ `testOperationalIssueDetected` — Operational issue detected
- ✅ `testPassedTimeRollsToTomorrowWithWarning` — Passed time rolls to tomorrow with warning
- ✅ `testPastCalendarDateRollsToNextYearWithWarning` — Past calendar date rolls to next year with warning
- ✅ `testRecurrenceVariants` — Recurrence variants
- ✅ `testRecurringWithTimeSchedulesNextFutureOccurrence` — Recurring with time schedules next future occurrence
- ✅ `testRelativeMinutes` — Relative minutes
- ✅ `testRemindEveryMondaySafety` — Remind every monday safety
- ✅ `testReminderWithoutTimeAsksForOne` — Reminder without time asks for one
- ✅ `testSameWeekdayIsFlagged` — Same weekday is flagged
- ✅ `testSarahNeedsHelpTalkTomorrow` — Sarah needs help talk tomorrow
- ✅ `testTalkToOvernightCoach` — Talk to overnight coach
- ✅ `testTimeWithoutMeridiemIsFlagged` — Time without meridiem is flagged

**CommitmentDetectorTests** (2 passed)

- ✅ `testFindsCommitmentsInMeetingNotes` — Finds commitments in meeting notes
- ✅ `testPlainProseYieldsNothing` — Plain prose yields nothing

**EisenhowerClassifierTests** (13 passed)

- ✅ `testAssociateDevelopmentIsScheduled` — Associate development is scheduled
- ✅ `testDeadlineAloneDoesNotMakeSomethingImportant` — Deadline alone does not make something important
- ✅ `testFollowUpCommitmentIsImportant` — Follow up commitment is important
- ✅ `testImmediateHazardIsDoFirst` — Immediate hazard is do first
- ✅ `testLowValueWorkIsEliminateCandidate` — Low value work is eliminate candidate
- ✅ `testManualClassification` — Manual classification
- ✅ `testMarketVisitPrepIsImportant` — Market visit prep is important
- ✅ `testQuadrantFlags` — Quadrant flags
- ✅ `testReasonsExplainTheSuggestion` — Reasons explain the suggestion
- ✅ `testSafetyIsImportantEvenWhenMarkedLowPriority` — Safety is important even when marked low priority
- ✅ `testSafetyWithDistantDeadlineStaysImportant` — Safety with distant deadline stays important
- ✅ `testUrgencyEscalationIsOnlyASuggestion` — Urgency escalation is only a suggestion
- ✅ `testUrgentWordsRaiseUrgency` — Urgent words raise urgency

**NotificationPlannerTests** (9 passed)

- ✅ `testCompletedAndPastItemsAreNotScheduled` — Completed and past items are not scheduled
- ✅ `testDailyBriefingsSkipPastTimes` — Daily briefings skip past times
- ✅ `testDateOnlyTaskGetsEndOfShiftNudge` — Date only task gets end of shift nudge
- ✅ `testDisabledCategories` — Disabled categories
- ✅ `testFollowUpTitleNamesThePerson` — Follow up title names the person
- ✅ `testPrivacyHidesTitles` — Privacy hides titles
- ✅ `testReminderAtDeadlineSuppressesDuplicateDeadlineAlert` — Reminder at deadline suppresses duplicate deadline alert
- ✅ `testReminderDeadlineAndOverdue` — Reminder deadline and overdue
- ✅ `testRespectsIOSPendingLimit` — Respects i o s pending limit

**PlanningTests** (12 passed)

- ✅ `testBriefingText` — Briefing text
- ✅ `testCarryForwardDay` — Carry forward day
- ✅ `testChosenTopPrioritiesWin` — Chosen top priorities win
- ✅ `testDayAgendaSections` — Day agenda sections
- ✅ `testPriorityRankerPrefersSafetyAndOverdue` — Priority ranker prefers safety and overdue
- ✅ `testRescheduleEarlierIsNotPostponement` — Reschedule earlier is not postponement
- ✅ `testRescheduleKeepsTimeAndShiftsReminder` — Reschedule keeps time and shifts reminder
- ✅ `testSchedulingAnUndatedTaskUsesDefaultReminder` — Scheduling an undated task uses default reminder
- ✅ `testShiftReview` — Shift review
- ✅ `testSnoozeOptions` — Snooze options
- ✅ `testUnfinishedWorkNeverDisappearsOvernight` — Unfinished work never disappears overnight
- ✅ `testWeeklyReview` — Weekly review

**RecurrenceTests** (12 passed)

- ✅ `testCodableRoundTrip` — Codable round trip
- ✅ `testDaily` — Daily
- ✅ `testEndDateStopsSeries` — End date stops series
- ✅ `testEveryOtherWeek` — Every other week
- ✅ `testEveryThreeDays` — Every three days
- ✅ `testMonthlyClampsToShortMonths` — Monthly clamps to short months
- ✅ `testNextOccurrence` — Next occurrence
- ✅ `testNoOccurrenceBeforeAnchor` — No occurrence before anchor
- ✅ `testOccurrenceKeysAreStable` — Occurrence keys are stable
- ✅ `testSpecificWeekdays` — Specific weekdays
- ✅ `testSummaries` — Summaries
- ✅ `testWeekdaysOnlySkipsWeekend` — Weekdays only skips weekend

### What the brief's examples produce

| Capture | Result |
|---|---|
| "Check with John tomorrow about his schedule." | Follow-up · **John** (new → confirm) · due tomorrow · reminder 7:00 AM (default, shown) · People |
| "Make sure dairy is cleaned up before Friday." | Task · **Dairy** · due **Thursday** ("before Friday → due Thu") · Q2 Schedule |
| "Follow up with Sarah about her availability next week." | Follow-up · **Sarah** · due next Monday · **flagged**: "next week" has no day |
| "Check VizPick results Thursday." | Task · due Thursday · Admin & Results · important · no person invented |
| "Remind me every Monday to review safety observations." | Reminder · **Every Monday** · Safety · always important |
| "Talk to the overnight Coach about the freight backlog." | Follow-up · role **Overnight Coach** · Freight · no date invented |

## Integration tests (run in Xcode)

`Tests/UnitTests/PersistenceTests.swift` uses an isolated in-memory SwiftData store and covers:
capture → follow-up + associate + interaction history · reuse of a known associate · Inbox saves raw text without inventing anything · idea → note · recurring capture → a week of occurrences, no duplicates on re-run · deleted occurrences aren't recreated · pausing removes only future untouched occurrences · complete / reopen / history · postponement counting · carry-forward (completed work untouched, nothing discarded) · manual quadrant override sticks and is logged · delegation awaits confirmation · Top 3 limit · checklist item → task · snooze · **backup round-trip** (export → restore into an empty store → identical counts and relationships, and a second restore is a no-op) · notification plan from real models.

`Tests/UITests/SecondBrainUITests.swift` launches with `-uiTesting -sampleData` (in-memory store, fictional data) and covers: Quick Capture saving a task · an ambiguous capture requiring **Confirm & Save** · four quadrants in the Matrix · End My Shift with Carry Forward · the weekly planner.

## Manual device checklist

| Area | Check |
|---|---|
| Capture | Type a capture and press Return: it saves in about 5 s. Mic: speak a capture and watch it transcribe ("on-device" shown when supported). |
| Ambiguity | "Follow up with Dana next week" shows Check before saving and Confirm & Save |
| Notifications (open) | A banner appears while the app is in the foreground |
| Notifications (background / suspended / closed) | Capture "test in 2 minutes", then background the app, lock the phone, or force-quit. The alert arrives each time. |
| Restart recovery | Restart the iPhone with reminders pending. They still fire. |
| Actions | Mark Complete from the lock screen completes the task (check in app). Snooze 15 Minutes re-alerts. Open Task opens the detail. |
| Widgets | Each family shows real tasks. The medium widget checkbox completes a task. Tapping opens the right screen. |
| Lock Screen | Rectangular shows the next reminder. Circular shows the priority count. |
| Siri | "Add a task to Second Brain" then "check the backroom tomorrow" gives a confirmation with the date |
| Accessibility | Settings › Accessibility › Larger Text at max: lists wrap, buttons remain reachable. VoiceOver: rows read as a single element, with labels on icon buttons. |
| Dark / Light | Settings › Appearance changes the whole app |
| Face ID | Turn on app lock, background the app, return: it's locked, and Face ID unlocks it |
| Backup | Export, Delete all data, Restore: everything comes back |

## How to reproduce

```bash
cd Packages/SecondBrainCore && swift test       # engine tests
python3 scripts/validate_project.py              # project structure
xcodebuild test -project SecondBrain.xcodeproj -scheme SecondBrain \
  -destination 'platform=iOS Simulator,name=iPhone 16'   # everything (on a Mac)
```
