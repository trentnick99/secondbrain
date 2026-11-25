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
| **Ask** | "What do I do if…": suggests vetted, offline guides (safety, equipment and freight, leading people, customers, ethics) plus your own store guides. Emergencies show "call 911" first. One tap searches Reddit (r/walmart) or the web in your browser. It doesn't generate answers. |
| **Huddle** | A 5-minute huddle from today: a seasonal safety message, yesterday's wins, the top three with owners, and shout-outs. Share it or save it. |
| **Shift timeline** | Your shift hour by hour, from an editable plan plus tasks with a time. Home shows "Now", with optional nudges at each block. |
| **Team lead lists** | Hand off tasks (confirmed) and text each team lead a clean list of titles and due times. |
| **Apple Watch** | Your top three, mark done, and a quick note from your wrist. |
| **Floor walk** | A safety-first checklist of your areas. Misses become tasks after you review them, and a summary can be saved to Notes. |
| **Scan, photo & walk notes** | Import reads text from a scanned page or a photo, on the phone. Speak walk notes turns each spoken sentence into an item. |
| **Shift handoff** | End My Shift → Share handoff texts what's open, what's coming up and what got done to the next coach. Associate follow-ups are left out by default. |
| **Severe weather** | Opt-in NWS warnings for your store's location: a Home banner and a notification around your shift. |
| **Shift on Lock Screen** | A Live Activity with time left, progress and your top three, also in the Dynamic Island. |
| **Quick Note** | Set the Action button to **Quick Note** to save a note from anywhere without opening the app. |
| **Your role & imports** | Choose your role and area (for example Food coach). Home, Tasks and the Season Planner focus on your areas plus store-wide items, and suggested routines fit your role. Paste a market email or notes, and the action items are sorted into yours, total store and no area. Other areas are hidden, only stated dates are used, and nothing saves until you review it. |
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
| **Siri & Shortcuts** | “Add a task to Second Brain”, “What are my priorities in Second Brain”, “Show my overdue tasks in Second Brain”, “Show my follow-ups in Second Brain”, “Remind me in Second Brain”, “End my shift in Second Brain”, “Import notes into Second Brain”, “Quick note in Second Brain”, “What's next in Second Brain”. Control Center buttons for Quick Capture, Floor Walk and Walk Notes, and an Off duty Focus filter. |
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
