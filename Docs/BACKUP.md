# Backup, restore & recovery

Your data lives in a SwiftData (SQLite) database on your iPhone, inside the App Group container so the widgets can read it. It persists when you close the app, restart the app, restart the phone, update the app, or re-install it from Xcode over an existing copy.

## Ways your data is protected

| Layer | What it covers | Where |
|---|---|---|
| **Daily automatic backup** | A full JSON snapshot each day you use the app, keeping the 14 most recent | Files app › On My iPhone › Second Brain › Backups |
| **Manual export** | A full JSON snapshot whenever you want one | Settings › Data › **Export backup…** (save to Files, iCloud Drive, AirDrop or email) |
| **iPhone / iCloud device backup** | iOS backs up the app's container with your normal iPhone backup | Automatic, if iPhone backups are on |
| **iCloud sync (optional)** | Keeps the database in your private iCloud and syncs between your devices | See [SIGNING.md](SIGNING.md) — paid membership required |

## Restoring

Go to Settings › Data › **Restore from backup…** and pick a `SecondBrain-*.json` file.

Restore **merges**:
- Records that aren't on the phone are added.
- Records that are newer in the backup replace older copies on the phone.
- Nothing on the phone is deleted.

Restoring the same file twice changes nothing. Relationships (tasks↔associates, notes, checklists, recurring series, history) are rebuilt.

**To move to a new iPhone:** export on the old phone, install the app on the new one, then restore.

## The backup format

The backup is readable JSON (`formatVersion: 1`). It contains `tasks`, `associates`, `notes`, `checklist`, `series`, `activity` and `shiftLogs`, with UUIDs linking related records and ISO-8601 dates. You can inspect it in any text editor. Treat backup files like the data itself: they include your notes and follow-ups.

## If something goes wrong

- **"Your saved data couldn't be opened" banner:** the app is running on a temporary store, so changes are not kept. Restart the app. If the banner persists, restore the most recent automatic backup from Files.
- **"iCloud sync isn't available for this build" banner:** sync was turned on without the iCloud capability. Your data is safe on the phone; turn sync off in Settings or add the capability.
- **Deleted something by mistake:** deleting needs confirmation and archiving is offered first. If you did delete it, restore yesterday's automatic backup. Merge mode brings back the missing records without touching anything else.
- **Delete all data:** Settings › Data › Delete all data asks twice. Export first if you might want the data later.
