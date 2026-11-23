# Architecture

## Layers

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ App (SwiftUI)        Features/  Dashboard · Capture · Tasks · Eisenhower ·     │
│                                 Associates · Notes · Planning · Shift ·       │
│                                 Review · Recurring · Settings · Onboarding    │
│                      Services/  NotificationService · SpeechCaptureService ·   │
│                                 CalendarService · AppLock · BackupService ·   │
│                                 AppMaintenance · BriefingAssistant · Sample   │
│                      Intents/   App Intents + App Shortcuts (Siri)             │
├──────────────────────────────────────┬────────────────────────────────────────┤
│ Shared (app + widget extension)      │ Widgets (WidgetKit extension)          │
│  Models/      SwiftData @Model types │  Timeline provider · Home/Lock Screen  │
│  Persistence/ Container, TaskActions,│  widgets · Control Center control      │
│               RecurrenceService,     │                                        │
│               CaptureSaver           │                                        │
│  Support/     AppGroup, AppSettings  │                                        │
│  Design/      Theme                  │                                        │
│  Intents/     CompleteTask, Capture  │                                        │
├──────────────────────────────────────┴────────────────────────────────────────┤
│ SecondBrainCore (Swift package, Foundation only — testable anywhere)          │
│  Capture/  NaturalLanguageParser, schedule/people extraction, lexicon,         │
│            CommitmentDetector                                                  │
│  Classification/ EisenhowerClassifier     Recurrence/ RecurrenceRule           │
│  Planning/ DayAgenda, PriorityRanker, ShiftReview, WeeklyReview,               │
│            BriefingBuilder, Rescheduler/SnoozeOption                           │
│  Notifications/ NotificationPlanner        Domain/ enums, TaskSnapshot          │
└───────────────────────────────────────────────────────────────────────────────┘
```

- **Business logic lives in the core package** and works on `TaskSnapshot` values, so the planner, notifications, widgets and Siri share one tested code path. It has 73 XCTest cases and builds on macOS and Linux.
- **All changes go through `TaskActions`**, which records history, handles recurrence, never discards unfinished work, and never assumes a delegation was accepted. Each save fires `DataChange`; the app hooks this to reschedule notifications and reload widgets (debounced).
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

Enums are stored as raw strings (`statusRaw`, `kindRaw`, …) with typed computed accessors. Urgency and importance are stored separately, and the quadrant is derived from them. `classificationIsManual` keeps your choices from being overwritten.

**CloudKit readiness:** every attribute has a default, all relationships are optional, there are no unique constraints, and inverses are declared on one side.

### Migrations

`SchemaV1` (a `VersionedSchema`) plus `SecondBrainMigrationPlan` are wired into the container. To evolve the model:
1. Copy the current model classes into an `enum SchemaV1 { @Model final class TaskItem {…} … }` namespace, which freezes v1.
2. Create `SchemaV2` with the new models.
3. Add `MigrationStage.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`, or a `.custom` stage, to `stages`.

Additive changes with defaults are lightweight migrations.

### Store location & failure handling

`PersistenceController` opens `SecondBrain.store` in the App Group container (`groupContainer: .identifier(...)`), or the app's own container if no group is provisioned. CloudKit is requested only when enabled in Settings. If opening fails, it retries locally, and as a last resort uses a temporary in-memory store with a visible warning. Your data is never silently replaced. The widget opens the same store with CloudKit off.

## Notifications design

1. `NotificationPlanner` (core) turns open task snapshots and preferences into the desired set of `PlannedNotification`s: reminders, deadlines, still-open alerts and daily briefings. The set is sorted and capped at 60 to stay under iOS's limit of 64.
2. `NotificationService.resyncNow()` compares that set with pending requests. It removes stale ones and adds or replaces the rest with `UNCalendarNotificationTrigger`s, then sets the badge.
3. A resync runs on every data change (debounced to 0.4 s), when the app becomes active, after notification actions, and in an opportunistic `BGAppRefreshTask`.
4. Actions are handled by `NotificationDelegate` (registered in `didFinishLaunching`, so actions work even when the app was closed) and `NotificationActionHandler`, which routes them through `TaskActions`.

Nothing assumes background execution. Recurring occurrences are created a week ahead, so their reminders are already scheduled even if the app isn't opened for days.

## Recurrence

`RecurrenceRule` evaluates daily, weekly (weekdays, interval) and monthly (day clamped) rules at day granularity. `RecurrenceService.materialize` creates missing occurrences from today to today+7 (and always the next one for long intervals). Occurrences are keyed by `(seriesID, yyyy-MM-dd)`. A dedupe pass removes untouched duplicates that might appear after an iCloud merge. Missed days aren't back-filled; the latest unfinished occurrence stays overdue.

## Navigation

`AppRouter` (`@Observable`) owns the selected tab, sheets and toasts. Deep links (`secondbrain://capture`, `task/<id>`, `shift`, `planner`, `overdue`, tab names) come from widgets, notifications and intents. `RouteRequest` passes routes from App Intents through shared defaults plus an in-process notification.

## Key decisions

| Decision | Why |
|---|---|
| iOS 18 minimum | Mature SwiftData, the `Tab` API, Control Center controls and interactive widgets |
| Swift 5 language mode | Avoids strict-concurrency churn when moving between Xcode versions. Main-actor isolation is explicit where it matters. |
| Rule-based intelligence | Works offline, is predictable and explainable, has no subscription, and is fully unit-tested. Apple's on-device model is optional polish. |
| Follow-ups as tasks | One pipeline for the dashboard, matrix, reminders, End My Shift and widgets |
| Local package for the engine | Fast tests without a simulator, and a hard boundary between logic and UI |
| Synchronized folders in the project | New files are picked up automatically, and the project file stays small and stable |
