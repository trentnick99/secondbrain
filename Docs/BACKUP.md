# Backup, restore & recovery

Your data lives in a SwiftData (SQLite) database on your iPhone, inside the App Group container so the widgets can read it. It persists when you close the app, restart the app, restart the phone, update the app, or re-install it from Xcode over an existing copy.

## Ways your data is protected

| Layer | What it covers | Where |
|---|---|---|
| **Daily automatic backup** | A full JSON snapshot each day you use the app, keeping the 14 most recent | Files app › On My iPhone › Coach Spark › Backups |
| **Manual export** | A full JSON snapshot whenever you want one | Settings › Data › **Export backup…** (save to Files, iCloud Drive, AirDrop or email) |
| **iPhone / iCloud device backup** | iOS backs up the app's container with your normal iPhone backup | Automatic, if iPhone backups are on |
| **iCloud sync** | Wired but not turned on in TestFlight builds | See [SIGNING.md](SIGNING.md) |

## Restoring

Go to Settings › Data › **Restore from backup…** and pick a `CoachSpark-*.json` file. Backups made before the rename (`SecondBrain-*.json`) restore the same way.

Restore **merges**:
- Records that aren't on the phone are added.
- Records that are newer in the backup replace older copies on the phone.
- Nothing on the phone is deleted.
- Standards lists and season events are added by id; ones already on the phone are kept as they are.
- Your store's process steps fill in only processes that have none on the phone.
- Season items you added or hid, and routines you added, are combined.
- Your schedule, role, shift plan, floor walk, store location and app settings are filled in only where the phone has none.
- Check-offs (Standards readings) are added once; they're never edited.

Restoring the same file twice changes nothing. Relationships (tasks↔associates, notes, checklists, recurring series, history) are rebuilt.

**To move to a new iPhone:** export on the old phone, install the app on the new one, then restore.

## The backup format

The backup is readable JSON (`formatVersion: 2`). It contains `tasks`, `associates`, `notes`, `checklist`, `series`, `activity`, `shiftLogs` and `checks` (Standards readings), with UUIDs linking related records and ISO-8601 dates. A `settings` object holds your Standards lists, process steps, season events, schedule, role, shift plan, floor walk, store location and app preferences. Caches and per-phone state (weather, Off duty, what you dismissed) are left out. Version 1 files from earlier builds still restore. You can inspect it in any text editor. Treat backup files like the data itself: they include your notes and follow-ups.

## If something goes wrong

- **"Your saved data couldn't be opened" banner:** the app is running on a temporary store, so changes are not kept. Restart the app. If the banner persists, restore the most recent automatic backup from Files.
- **Deleted something by mistake:** deleting needs confirmation and archiving is offered first. If you did delete it, restore yesterday's automatic backup. Merge mode brings back the missing records without touching anything else.
- **Delete all data:** Settings › Data › Delete all data asks twice. It removes every record, your lists, readings, season events, schedule, role, shift plan, floor walk, store location and every automatic backup on the iPhone, so export first (and save the file somewhere else) if you might want the data later. Notification and appearance settings stay.
