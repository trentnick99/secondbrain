# Known limitations

## Build & verification

- **Not yet compiled by Xcode.** The project was produced in a Linux environment with no Xcode and no iOS SDK. The engine package compiles and passes 73 tests, every Swift file passes the Swift parser, and the project file was validated. The SwiftUI, SwiftData, WidgetKit and App Intents code still needs its first Xcode build, and a few small fixes from SDK differences are possible. The XCTest integration and UI tests haven't been run yet.
- **Not installed on a device.** Notification delivery, widgets, Siri phrases, Face ID and speech capture need the manual checks listed in [TEST_RESULTS.md](TEST_RESULTS.md).

## Platform constraints (iOS rules)

- **Background work isn't guaranteed.** iOS decides whether and when background refresh runs. Reminders don't depend on it, because they're scheduled ahead, but the "week ahead" of recurring occurrences is only extended when the app opens or iOS grants a refresh. If the app isn't opened for over a week, daily recurring reminders past that week won't be scheduled until you open it.
- **Pending notification limit.** iOS keeps 64 pending local notifications per app. Second Brain keeps the soonest 60 and tops them up on every open or change. With a very large number of timed reminders far in the future, the later ones are scheduled as earlier ones fire, once the app is opened.
- **Briefing notification text** is computed when it's scheduled. If you change tasks on another device (with iCloud sync) without opening the app on this one, the morning briefing's counts can be out of date. Opening the app refreshes them.
- **Widget refresh budget.** iOS limits how often widgets refresh. The app reloads them after every change, but timing is ultimately up to iOS.
- **Widget checkbox vs. open app.** Completing a task from a widget writes to the shared database from the widget process. If the app is already open in the background, it may show the old state until it's reopened. Any reminder already scheduled for that task can still fire once, until the app next runs and resyncs.
- **Free Apple ID signing** expires after 7 days (re-run from Xcode). TestFlight and iCloud sync need the paid Apple Developer Program.

## Product scope

- **Natural-language understanding is rule-based and English-only.** It handles the common phrasing of a shift: dates, times, weekdays, "before Friday", "end of shift", recurrence, names after "with/to/ask/tell", and "X needs/asked". Unusual phrasing may need a tap on **Adjust**. Names are only taken from clear patterns or your Associates list, and new names always ask for confirmation.
- **Rich text:** notes are structured plain text (body plus checklist), not styled text.
- **Calendar:** read-only display, conflict warnings and add-on-request. There's no two-way task↔calendar sync.
- **iCloud sync** is wired and the model is CloudKit-compatible, but it needs the capability added at build time and hasn't been exercised across two devices.
- **Apple Intelligence briefing** needs iOS 26 on an Apple Intelligence–capable iPhone. Otherwise the standard briefing is used.
- **Week start** defaults to Saturday, since many retail schedules run Saturday–Friday. Change it in Settings.
- **No employer integrations,** by design: no connection to internal systems, no scraping, no stored work credentials.
