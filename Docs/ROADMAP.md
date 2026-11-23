# Roadmap

## Next (after the first device build)

1. **First Xcode build and simulator run:** fix any SDK-level compile issues, run ⌘U, and record the results in TEST_RESULTS.md.
2. **On-device notification pass** using the manual checklist (open, background, suspended, closed, restart).
3. **SwiftData history for widget writes:** use `ModelContext` history (iOS 18) so tasks completed from a widget appear immediately in an already-running app.
4. **Snapshot tests** for key screens in Dynamic Type sizes, dark and light.

## Near term

- **Shift templates:** a "start of shift" checklist (safety walk, huddle, freight check) that you can tick off from a widget.
- **Live Activity** for the current shift, showing the next reminder and open commitments on the Lock Screen and Dynamic Island.
- **Smarter capture:** learn your phrasing, such as your department nicknames and common people, and suggest categories from past choices. All on-device.
- **Batch triage** for the Inbox: sort several captured items in one pass.
- **Follow-up templates:** common requests like schedule questions, PTO and training with prefilled commitments.
- **Interactive widget actions:** snooze and "move to tomorrow" from the medium and large widgets.
- **Focus filters:** show only shift-relevant tasks when a work Focus is on.

## Later

- **iPad and Mac (Catalyst / Designed for iPad)** layouts for weekly planning at a desk.
- **Apple Watch** companion: complications, quick capture by voice, complete from the wrist.
- **Two-way calendar sync** for scheduled Q2 work blocks.
- **Optional external AI provider**, bring-your-own-key and off by default, for long-form meeting-note summaries.
- **Localization** (Spanish first), including the capture parser's vocabulary.
- **Shared lists** between coaches via CloudKit sharing, keeping the same privacy rules.
