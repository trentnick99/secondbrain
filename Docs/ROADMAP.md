# Roadmap

## Shipped

- **Builds 1–12:** capture, the Eisenhower Matrix, follow-ups, End My Shift, recurring tasks, notifications, widgets, Siri and Shortcuts, the Season Planner, Store Terms, Standards, Floor walk, Huddle, Shift timeline, the Live Activity, the Apple Watch app, the Off duty Focus filter and the rename to Coach Spark.
- **Build 13 (audit stages 1–4):** complete backups (lists, schedule, role and settings) and a delete that removes them too; one sheet at a time, so deep links always open; one save path that shows a message when a save fails; a Home clock that stays current; the AI briefing removed; Settings holds settings only; End My Shift with Carry all at the top and swipe actions; cosmetic fixes for large text and edge fades; SwiftLint in CI; the shipped database schema frozen with tests.
- **Build 14 (audit stage 5):** Standards check-offs with readings and a task for a miss; sharing lists as text; your store's own season events with prep steps; Sort all for the Inbox; a move-to-next-shift button on widgets; check-offs and season events in backups; Home loads only open and recently finished tasks, so a year of history doesn't slow it; the first database upgrade (V1 → V2), covered by tests.

## Next

1. **On-device pass** with the manual checklist in [TEST_RESULTS.md](TEST_RESULTS.md): notifications (open, background, closed, restart), widgets, Face ID, the Watch, the Live Activity, and upgrading a phone that has real data.
2. **SwiftData history for widget writes:** use `ModelContext` history (iOS 18) so tasks completed or moved from a widget appear immediately in an already-running app.
3. **Snapshot tests** for key screens at large text sizes, in dark and light.
4. **iCloud sync:** turn it on in a build and test it across two devices before offering it.

## Near term

- **Start-of-shift checklist:** safety walk, huddle and freight check that you can tick off from a widget.
- **Check-off history:** a week of readings per list, and a reminder to take readings at set times.
- **Smarter capture:** learn your phrasing, such as department nicknames and common people, and suggest categories from past choices. All on the phone, with rules, not AI.
- **Follow-up templates:** common requests like schedule questions, PTO and training, with prefilled commitments.
- **More widget actions:** snooze from the medium and large widgets.

## Later

- **iPad and Mac (Designed for iPad)** layouts for weekly planning at a desk.
- **Watch complications** and voice capture from the wrist.
- **Two-way calendar sync** for scheduled Q2 work blocks.
- **Localization** (Spanish first), including the capture parser's vocabulary.
- **Shared lists** between coaches via CloudKit sharing, keeping the same privacy rules.
