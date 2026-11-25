# Known limitations

## Build & verification

- **Compiled and tested on a cloud Mac.** GitHub Actions with Xcode 26.6 builds the app, widget and tests, and the engine and SwiftData integration tests pass on an iOS 26.5 simulator. See [TEST_RESULTS.md](TEST_RESULTS.md).
- **Device-only behavior isn't covered by CI.** Builds go to TestFlight, but notification delivery, widgets (including the next-shift button clearing reminders), Siri phrases, Face ID, speech capture, the Watch app, the Live Activity and the SwiftData upgrade on a phone with real data are checked by hand, using [TEST_RESULTS.md](TEST_RESULTS.md).
- **GitHub's Apple-silicon Macs were at capacity** during setup, so the workflows default to `macos-26-intel`. You can pick another runner when you start a run.

## Platform constraints (iOS rules)

- **Background work isn't guaranteed.** iOS decides whether and when background refresh runs. Reminders don't depend on it, because they're scheduled ahead, but the "week ahead" of recurring occurrences is only extended when the app opens or iOS grants a refresh. If the app isn't opened for over a week, daily recurring reminders past that week won't be scheduled until you open it.
- **Pending notification limit.** iOS keeps 64 pending local notifications per app. Task alerts take the soonest 60, or fewer when shift timeline nudges are scheduled, so the total stays within 64; they're topped up on every open or change. With a very large number of timed reminders far in the future, the later ones are scheduled as earlier ones fire, once the app is opened.
- **Briefing notification text** is computed when it's scheduled. If you change tasks from a widget, Siri or the Watch without opening the app, the morning briefing's counts can be out of date. Opening the app refreshes them.
- **Widget refresh budget.** iOS limits how often widgets refresh. The app reloads them after every change, but timing is ultimately up to iOS.
- **Widget checkbox vs. open app.** Completing a task from a widget writes to the shared database from the widget process. If the app is already open in the background, it may show the old state until it's reopened. The widget clears that task's pending reminder, deadline and still-open alerts right away; any repeat reminders are rescheduled the next time the app runs.
- **Free Apple ID signing** expires after 7 days (re-run from Xcode). TestFlight and iCloud sync need the paid Apple Developer Program.

## Product scope

- **Natural-language understanding is rule-based and English-only.** It handles the common phrasing of a shift: dates, times, weekdays, "before Friday", "end of shift", recurrence, names after "with/to/ask/tell", and "X needs/asked". Unusual phrasing may need a tap on **Adjust**. Names are only taken from clear patterns or your Associates list, and new names always ask for confirmation.
- **Rich text:** notes are structured plain text (body plus checklist), not styled text.
- **Calendar:** read-only display, conflict warnings and add-on-request. There's no two-way task↔calendar sync.
- **iCloud sync** is wired and the model is CloudKit-compatible, but it's compiled out of TestFlight builds (the Settings toggle is hidden) and hasn't been exercised across two devices.
- **No AI.** Briefings, suggestions and the weekly review come from built-in rules. That keeps them predictable and offline, but they won't rephrase things or understand unusual wording.
- **Standards check-offs read simple limits.** A reading is judged automatically only when the standard reads like "-10°F or colder", "33–38°F" or "135°F or hotter". Anything else asks you whether it's within the standard. Readings are a personal record, not an official temperature log.
- **Week start** defaults to Saturday, since many retail schedules run Saturday–Friday. Change it in Settings.
- **Store Terms is unofficial.** The reference was compiled from public employee discussions and retail references. Terms change and vary by store and market; entries are tagged older, informal or "varies" where known. Edit `StoreGlossary.swift` to correct or add terms.
- **Season Planner dates.** Holidays and the fiscal week are calculated. Sales events are only those Walmart has announced (through Cyber Monday 2026) and must be added in an app update for later years. Seasonal set timing is typical only. Regional items (hurricanes, winter weather, Lawn & Garden, back-to-school) can be hidden. Your store's own events are whatever you enter; the app never fills them in.
- **Privacy nudges are keyword-based.** They catch common phrasing ("write up", "DA", "NCNS", "FMLA"), not every way of describing sensitive information, and they never block saving.
- **No employer integrations,** by design: no connection to internal systems, no scraping, no stored work credentials.
