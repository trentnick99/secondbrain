# Architecture

## Layers

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ App (SwiftUI)        Features/  Dashboard · Capture · Tasks · Eisenhower ·     │
│                                 Associates · Notes · Standards · Walk ·        │
│                                 Huddle · Planning · Shift · Season · Review ·  │
│                                 Import · Weather · Settings · Onboarding       │
│                      Services/  NotificationService · BackupService ·          │
│                                 AppMaintenance · WeatherAlertService ·         │
│                                 WatchSyncService · ShiftActivityController ·   │
│                                 Speech · TextRecognizer · Calendar · AppLock   │
│                      Intents/   App Intents + App Shortcuts (Siri, Action btn) │
├──────────────────────────────────────┬────────────────────────────────────────┤
│ Shared (app + widget extension)      │ Widgets (WidgetKit extension)          │
│  Models/      SwiftData @Model types │  Home/Lock Screen widgets · controls · │
│               (frozen SchemaV1 + V2) │  Live Activity                         │
│  Persistence/ Container, TaskActions,├────────────────────────────────────────┤
│               RecurrenceService,     │ Watch (watchOS app)                    │
│               CaptureSaver           │  Top 3 and shift summary over          │
│  Support/     AppGroup, AppSettings, │  WatchConnectivity                     │
│               UserContent            │                                        │
│  Design/      Theme                  │                                        │
│  Intents/     CompleteTask, NextShift│                                        │
├──────────────────────────────────────┴────────────────────────────────────────┤
│ SecondBrainCore (Swift package, Foundation only — testable anywhere)          │
│  Capture/  NaturalLanguageParser, schedule/people extraction, lexicon,         │
│            CommitmentDetector, NoteImporter, SensitiveContent                  │
│  Classification/ EisenhowerClassifier     Recurrence/ RecurrenceRule           │
│  Planning/ DayAgenda, ShiftReview, WeeklyReview, RetailCalendar (+ your store  │
│            events), FloorWalk, ShiftTools, BriefingBuilder                     │
│  Guidance/ Standards, TemperatureRule, CoachGuides (13 store processes)        │
│  Notifications/ NotificationPlanner (+ shared 64-notification budget)          │
│  Weather/ WeatherAlerts (weather.gov)     Domain/ enums, TaskSnapshot          │
└───────────────────────────────────────────────────────────────────────────────┘
```
- **Business logic lives in the core package** and works on `TaskSnapshot` values, so the planner, notifications, widgets and Siri share one tested code path. It has 184 XCTest cases and builds on macOS and Linux.
- **All changes go through `TaskActions`**, which records history, handles recurrence, never discards unfinished work, and never assumes a delegation was accepted. `TaskActions.save` is the one save path: it logs failures with `os.Logger`, shows a "Couldn't save" toast through `DataChange.saveFailed`, and fires `DataChange`, which the app hooks to reschedule notifications, reload widgets, refresh the Live Activity and update the Watch (debounced).
- **Widget actions run in the widget process**, where `DataChange` handlers aren't set up. `CompleteTaskIntent` and `MoveToNextShiftIntent` therefore clear that task's pending reminders themselves; the app reschedules everything when it next becomes active.
- **Views stay small**: shared rows, cards, swipe/context actions (`TaskInteractions`), the reschedule sheet, quadrant and recurrence pickers.

## Data model (SwiftData, CloudKit-compatible)

| Model | Purpose | Key relationships |
|---|---|---|
| `TaskItem` | Tasks, follow-ups (`kind = .followUp` + request/commitment/conversationDate), reminders, operational issues | associate, subtasks (ChecklistItem), notes (many-to-many), activity |
| `Associate` | A person; non-sensitive context only | tasks, notes, series, activity (interaction history) |
| `Note` | Structured note with a type, tags, pinning and a checklist | associate, linkedTasks, checklist |
| `ChecklistItem` | A subtask or note checklist line; can be converted to a task | task or note |
| `RecurrenceSeries` | A recurring definition (`ruleJSON`, time, template fields, paused/discontinued, skipped keys) | associate; occurrences linked by `seriesID` |
| `ActivityEvent` | Task history and associate interactions | task, associate |
| `ShiftLog` | One record per End My Shift | — |
| `StandardCheck` (V2) | One temperature reading or quality check against a line of your Standards lists, with the names and standard it was made with | — (refers to the list by id; lists live in settings) |

Enums are stored as raw strings (`statusRaw`, `kindRaw`, …) with typed computed accessors. Urgency and importance are stored separately, and the quadrant is derived from them. `classificationIsManual` keeps your choices from being overwritten.

**CloudKit readiness:** every attribute has a default, all relationships are optional, there are no unique constraints, and inverses are declared on one side.

### Migrations

The schema is versioned and frozen:

- **`SchemaV1`** is what builds 1–12 shipped. The seven model classes are nested in `SchemaV1` (`extension SchemaV1 { @Model final class TaskItem … }`) with top-level typealiases (`typealias TaskItem = SchemaV1.TaskItem`).
- **`SchemaV2`** adds `StandardCheck` and reuses the V1 classes unchanged, so V1 → V2 is a lightweight migration that only adds a table.
- **`SchemaTests`** (integration tests) checks SchemaV1's Core Data entity hashes against the values recorded from the shipped app, checks that V2 leaves those tables untouched, and opens a store written with SchemaV1 through the current migration plan.

To change a model in the future:
1. Copy the class into a new `SchemaV3` namespace and change the copy. Leave the older versions alone.
2. Point the typealias at the V3 copy, list it in `SchemaV3.models`, and make `PersistenceController.schema` use V3.
3. Add `MigrationStage.lightweight(fromVersion: SchemaV2.self, toVersion: SchemaV3.self)` (or `.custom`) to `stages`.
4. Run the integration tests. The V1 hash test must still pass; if it doesn't, a frozen version was edited.

### Content kept in settings

Some of your content is small JSON in App Group `UserDefaults` rather than the database: Standards lists, process steps, Season planner events, the schedule, role, shift plan, floor walk, season choices and the store's location. `UserContent` (Shared/Support) is the registry for these keys:

- **Backups** (format 2) carry them in a `settings` section. Restores merge without overwriting anything on the phone: Standards lists are added by id, process steps by process, season and routine choices are combined, and everything else is filled in only when the phone doesn't have it.
- **Delete all data** removes them along with the database and every automatic backup. App preferences (notifications, appearance, App Lock) stay.

### Store location & failure handling

`PersistenceController` opens `SecondBrain.store` in the App Group container (`groupContainer: .identifier(...)`), or the app's own container if no group is provisioned. CloudKit is requested only when enabled in Settings. If opening fails, it retries locally, and as a last resort uses a temporary in-memory store with a visible warning. Your data is never silently replaced. The widget opens the same store with CloudKit off.

## Notifications design

1. `NotificationPlanner` (core) turns open task snapshots and preferences into the desired set of `PlannedNotification`s: reminders, deadlines, still-open alerts and daily briefings. The set is sorted and capped at 60, or less when other pending notifications (shift timeline nudges) are scheduled: `NotificationPlanner.taskBudget(reserved:)` keeps the total within iOS's limit of 64.
2. `NotificationService.resyncNow()` compares that set with pending requests. It removes stale ones and adds or replaces the rest with `UNCalendarNotificationTrigger`s, then sets the badge.
3. A resync runs on every data change (debounced to 0.4 s), when the app becomes active, after notification actions, and in an opportunistic `BGAppRefreshTask`.
4. Actions are handled by `NotificationDelegate` (registered in `didFinishLaunching`, so actions work even when the app was closed) and `NotificationActionHandler`, which routes them through `TaskActions`.

Nothing assumes background execution. Recurring occurrences are created a week ahead, so their reminders are already scheduled even if the app isn't opened for days.

## Recurrence

`RecurrenceRule` evaluates daily, weekly (weekdays, interval) and monthly (day clamped) rules at day granularity. `RecurrenceService.materialize` creates missing occurrences from today to today+7 (and always the next one for long intervals). Occurrences are keyed by `(seriesID, yyyy-MM-dd)`. A dedupe pass removes untouched duplicates that might appear after an iCloud merge. Missed days aren't back-filled; the latest unfinished occurrence stays overdue.

## Navigation

`AppRouter` (`@Observable`) owns the selected tab, one `ActiveSheet` and toasts. Exactly one sheet is open at a time, so a deep link, notification or Siri route always replaces whatever is showing (Home's own More tools sheet opens its choice after it closes). Deep links (`secondbrain://capture`, `task/<id>`, `shift`, `planner`, `overdue`, `standards?q=`, `walk`, `huddle`, `timeline`, tab names) come from widgets, notifications and intents. `RouteRequest` passes routes from App Intents through shared defaults plus an in-process notification.

## Key decisions

| Decision | Why |
|---|---|
| iOS 18 minimum | Mature SwiftData, the `Tab` API, Control Center controls and interactive widgets |
| Swift 5 language mode | Avoids strict-concurrency churn when moving between Xcode versions. Main-actor isolation is explicit where it matters. |
| Rule-based intelligence, no generated text | Works offline, is predictable and explainable, has no subscription, and is fully unit-tested. Generated answers were removed because answers not tailored to the store did more harm than good. |
| Follow-ups as tasks | One pipeline for the dashboard, matrix, reminders, End My Shift and widgets |
| Local package for the engine | Fast tests without a simulator, and a hard boundary between logic and UI |
| Synchronized folders in the project | New files are picked up automatically, and the project file stays small and stable |
| Lint in CI | SwiftLint runs a small strict rule set (crash risks and obvious mistakes, not style) on every build: `.swiftlint.yml` |
