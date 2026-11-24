# Project Second Brain

A native iPhone app (Swift · SwiftUI · SwiftData) for a retail store coach. Capture what associates ask, what managers assign and what you notice in a few seconds, sort it with an Eisenhower Matrix, get reminded, and finish each shift knowing what's done and what's left.

**Capture now · Organize automatically · Prioritize intelligently · Remember later · Follow through**

> Independent personal productivity app. Not affiliated with or connected to any employer or retailer. Sample data is fictional.

## Quick start — no Mac (Windows + GitHub + TestFlight)

GitHub's cloud Macs build the app; TestFlight installs it on your iPhone. Follow [Docs/GITHUB_TESTFLIGHT.md](Docs/GITHUB_TESTFLIGHT.md) (one-time setup, all in a browser).

## Quick start (on a Mac)

1. Install **Xcode 16 or later** (Xcode 26 recommended) from the Mac App Store.
2. Open `SecondBrain.xcodeproj`.
3. Edit `Config/Signing.xcconfig`: set `DEVELOPMENT_TEAM` to your Team ID and change `BASE_BUNDLE_ID` to something unique, such as `com.yourname.secondbrain`.
4. Plug in your iPhone (with Developer Mode on), choose it as the run destination, and press **⌘R**.

You'll find the full walkthrough in [Docs/INSTALL.md](Docs/INSTALL.md) and the signing details in [Docs/SIGNING.md](Docs/SIGNING.md).

## What's inside

| Area | Highlights |
|---|---|
| **Your store** | Knows coach and team lead roles, the store manager, and areas like AP, ACC and OPD. "Have Jordan work the truck" hands a task to a team lead, and it stays Waiting until they confirm. A weekly 7–5 / 10–8 / 12–10 schedule drives "end of shift", briefings and End My Shift. |
| **Season Planner** | Shows the next 12 months: holidays, Walmart's announced deal events, typical seasonal sets, clock changes and weather safety. Each item has prep steps you add as tasks with a tap. Home shows what's coming up and the fiscal week. |
| **Store terms** | Capture understands Stock 1–3, CAP, O/N, MOD, department numbers, OPD and Fresh terms, and safety equipment. It also includes a searchable, offline reference of about 500 store terms, flagged when they're older, informal or vary by store. A gentle note appears if you start typing disciplinary, medical, attendance or AP case details. |
| **Quick Capture** | A + button on every tab, plus a Control Center / Action button control, Siri and widget links. Type or speak (on-device speech). The capture is interpreted live: person, department, date, time, reminder, repeat, category, priority and quadrant. Anything ambiguous is shown for confirmation first. “Inbox” saves the raw text unchanged. |
| **Home** | Today's top 3, overdue, Do First, follow-ups, due today, upcoming reminders, tomorrow and the rest of the week, recurring work, completed today, a daily briefing, and an **End My Shift** button. |
| **Eisenhower Matrix** | A 2×2 overview with drag-and-drop between quadrants, and swipeable full-screen quadrants. Each suggestion explains its reasons. Safety and compliance work always stays important. Q4 items are never auto-deleted, and delegation is never assumed accepted. |
| **Associate follow-ups** | Each follow-up records the request, your commitment, the conversation date and the follow-up date. Follow-ups are grouped into overdue, today, upcoming, waiting and resolved. Each person has an interaction history. |
| **Tasks** | Every required field, all seven statuses, four priorities, subtasks, duplication, archive, reopen and delete with confirmation. History is recorded. |
| **Planning** | Daily planner (choose 3 priorities) and a weekly planner (7 days, drag tasks between days). |
| **End My Shift** | Completed, unfinished, overdue, commitments, unconfirmed hand-offs, deadlines, Q2 work, and suggested priorities for tomorrow. You choose to carry each item forward, reschedule it, complete it or leave it. |
| **Notes** | General, associate, meeting, department, operational, safety and idea notes. Tags, pinning, search and checklists, with items convertible to tasks. **Find follow-ups** detects commitments in a note. |
| **Recurring** | Daily, weekdays, specific weekdays, monthly and custom intervals. A week is generated ahead with no duplicates. Pause, edit or discontinue. |
| **Notifications** | Local, scheduled ahead of time, and working offline. Actions: Mark Complete, Snooze 15 min / 1 hr, Tomorrow Morning, Open Task. Also deadline, still-open and daily-briefing alerts, privacy previews and a badge. |
| **Widgets** | Home Screen (small, medium with tappable checkboxes, large with matrix counts and follow-ups) and Lock Screen (circular, rectangular, inline), all showing real data. |
| **Siri & Shortcuts** | “Add a task to Second Brain”, “What are my priorities in Second Brain”, “Show my overdue tasks in Second Brain”, “Show my follow-ups in Second Brain”, “Remind me in Second Brain”, “End my shift in Second Brain”. |
| **Optional extras** | Apple Calendar integration (events, conflicts, add-to-calendar on request), an Apple Intelligence briefing (iOS 26+), iCloud sync, Face ID lock, JSON backup and restore with daily automatic backups. |

## Repository layout

```
SecondBrain.xcodeproj      Ready-to-open project (Xcode 16+, synchronized folders)
App/                       iPhone app target (SwiftUI screens, services, App Intents, assets)
Shared/                    Compiled into app + widget: SwiftData models, persistence, task rules, theme
Widgets/                   WidgetKit extension (Home/Lock Screen widgets, Control Center control)
Packages/SecondBrainCore/  Platform-independent engine + 129 unit tests (runs anywhere with `swift test`)
Tests/UnitTests            SwiftData integration tests (Xcode)
Tests/UITests              XCUITest end-to-end workflow (Xcode)
Config/                    Info.plists, entitlements, Signing.xcconfig
Docs/                      Install, signing, backup, features, architecture, tests, limitations, roadmap
scripts/                   Project generator, validators, CI helpers
.github/workflows/         Build & Test (every push) and TestFlight (manual) on GitHub's cloud Macs
project.yml                Optional XcodeGen definition (alternative to the committed project)
```

## Docs

- [GITHUB_TESTFLIGHT.md](Docs/GITHUB_TESTFLIGHT.md): build and install from Windows (GitHub Actions + TestFlight)
- [INSTALL.md](Docs/INSTALL.md): build, test and install on your iPhone from a Mac (Xcode)
- [SIGNING.md](Docs/SIGNING.md): Apple Developer account and signing requirements
- [FEATURES.md](Docs/FEATURES.md): feature guide and the end-to-end workflow
- [BACKUP.md](Docs/BACKUP.md): backup, restore and recovery
- [ARCHITECTURE.md](Docs/ARCHITECTURE.md): modules, data model, migrations, notification design
- [TEST_RESULTS.md](Docs/TEST_RESULTS.md): what was tested where, with results
- [LIMITATIONS.md](Docs/LIMITATIONS.md): known limitations
- [ROADMAP.md](Docs/ROADMAP.md): future development
- [CHECKLIST.md](Docs/CHECKLIST.md): development checklist by phase
