# Development checklist

| Phase | Item | Status |
|---|---|---|
| 1 | Inspect environment (Linux, no Xcode; Swift 5.10 toolchain extracted for engine tests) | ✅ |
| 1 | Inspect existing work: kept the existing `SecondBrainCore` engine (parser, classifier, recurrence, planners) | ✅ |
| 1 | Architecture: core package + shared SwiftData layer + app + widget extension | ✅ |
| 2 | Xcode project (app, widgets, unit tests, UI tests; synchronized folders; shared schemes) | ✅ generated + validated |
| 2 | Design system (charcoal / teal theme, cards, chips, quadrant colors, dark and light) and app icon | ✅ |
| 3 | SwiftData models (CloudKit-compatible), versioned schema + migration plan, App Group store, failure fallback | ✅ |
| 4 | Quick Capture (text, dictation, on-device speech, live interpretation, ambiguity confirmation, Inbox) | ✅ |
| 4 | Task management (all fields, 7 statuses, 4 priorities, subtasks, duplicate, archive, reopen, delete with confirmation, history) | ✅ |
| 5 | Eisenhower Matrix (overview, drag-and-drop, swipe pager, reasons, safety lock, escalation suggestions, Q4 never auto-deleted) | ✅ |
| 6 | Associate follow-ups (request / commitment, sections, search, people, interaction history, related tasks, privacy reminder) | ✅ |
| 7 | Notes (7 types, tags, pinning, search, checklist → task, link tasks, Find follow-ups) | ✅ |
| 8 | Daily planner (Top 3) and weekly planner (7 days, move between days) | ✅ |
| 9 | Local notifications (reminders, deadline, still-open, briefing; actions; snooze; permission once; resync) | ✅ |
| 9 | Recurring tasks (daily, weekdays, weekdays list, monthly, intervals; no duplicates; pause / discontinue) | ✅ |
| 10 | Widgets (small, medium, large, 3 Lock Screen families, Control Center control, interactive complete) | ✅ |
| 10 | App Intents and Siri phrases (add, remind, priorities, overdue, follow-ups, end shift, quick capture) | ✅ |
| 11 | Optional Apple Calendar (events, conflicts, add on request); briefing from built-in rules (AI briefing removed in build 13) | ✅ |
| 11 | End My Shift and Weekly Review | ✅ |
| 11 | Face ID lock, privacy previews, backup / restore, daily automatic backup, fictional sample data | ✅ |
| 12 | Engine tests: 73/73 passing; syntax check of all files; project validation | ✅ |
| 12 | Xcode build (cloud Mac, Xcode 26.6) and 17 integration tests | ✅ GitHub Actions |
| 12 | GitHub Actions: Build & Test on push; manual TestFlight upload | ✅ |
| 13 | Installation, signing, backup, features, architecture, limitations, roadmap docs | ✅ |
| 13 | Install on iPhone | ⏳ TestFlight, after Apple Developer setup (see GITHUB_TESTFLIGHT.md) |
