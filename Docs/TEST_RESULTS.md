# Test results

_Run on 2026-11-23 in the build environment (Linux x86_64, Swift 5.10.1). Xcode was not available there._

## Summary

| Suite | Where it runs | Status here |
|---|---|---|
| **SecondBrainCoreTests**: 73 tests covering the parser, Eisenhower classifier, recurrence, agenda, End My Shift, weekly review, notification planner, rescheduling and commitment detection | `swift test` (Mac or Linux) and Xcode ⌘U | ✅ **73 / 73 passed** (0 failures, 0.28 s) |
| **Swift syntax check**: every app, widget and test file (47 files) parsed with `swiftc -parse` | Linux | ✅ 47 / 47 parse cleanly |
| **Project validation**: `project.pbxproj` parsed, all object references resolve, synchronized folders and file references exist, schemes, plists, entitlements and asset JSON are well-formed | `python3 scripts/validate_project.py` | ✅ valid |
| **Symbol cross-check**: every `TaskActions`, `RecurrenceService`, `AppSettings`, … member referenced by the app exists | script | ✅ 0 unresolved |
| **SecondBrainTests**: 17 SwiftData integration tests | Xcode, iOS Simulator | ⏳ **Not run.** These need Xcode on a Mac. |
| **SecondBrainUITests**: 5 end-to-end UI tests | Xcode, iOS Simulator | ⏳ **Not run.** These need Xcode on a Mac. |
| **Full app compile (SwiftUI / SwiftData / WidgetKit)** | Xcode | ⏳ **Not done.** The iOS SDK isn't available on Linux. |
| **On-device checks**: notifications (open / background / suspended / closed / after restart), widgets, Siri, Face ID, speech | iPhone | ⏳ Manual checklist below |

Nothing in this project claims to have been compiled by Xcode, installed on an iPhone or run on a simulator. Those steps happen on your Mac (see [INSTALL.md](INSTALL.md)).

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
