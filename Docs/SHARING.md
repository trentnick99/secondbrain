# Sharing Second Brain with other coaches (TestFlight public link)

TestFlight can give the app a public link that anyone can open on an iPhone, for up to 10,000 testers. Apple reviews the first build shared this way (Beta App Review), which usually takes about a day. Each tester's data stays on their own phone.

## 1. Fill in Test Information (once)

In **App Store Connect › Apps › Second Brain for Coaches › TestFlight › Test Information**:

- **Beta App Description:** paste the text below.
- **Feedback Email:** the address where you want testers' feedback.
- **Privacy Policy URL:** `https://github.com/trentnick99/secondbrain/blob/main/Docs/PRIVACY.md`
- **Beta App Review Information:** your name, phone and email (Apple only uses these if a reviewer has questions). Leave "Sign-in required" off; the app has no accounts.

### Beta App Description (paste)

> Second Brain for Coaches is a personal organizer for retail store leaders. Capture tasks and follow-ups in plain language and see what matters in an Eisenhower Matrix. You can also run a floor walk, build a 5-minute huddle, plan your shift hour by hour, and hand off to the next coach with End My Shift. Ask suggests practical "what do I do if…" guides, and you can add your own store's steps. Everything stays on your iPhone, with no accounts and no tracking. This is an independent app, not affiliated with or endorsed by any retailer. Don't store medical, disciplinary or other confidential personnel information.

### What to Test (paste for each build)

> Try capturing a few tasks, setting your role in Settings, a floor walk, the Huddle, and Ask. Tell us what's confusing or missing.

## 2. Create the public group

1. **TestFlight › External Testing › +** (next to "External Testing"), and name it "Coaches".
2. In the group, open **Builds › +**, pick the latest build, and add the "What to Test" text.
3. Tap **Submit for Review**. When Apple approves it, the group shows **Public Link**: turn it on and copy the link.
4. Optional: set a tester limit so the link can't spread too far.

Anyone with the link installs TestFlight, then the app. New builds you add to the group reach them automatically after review (later builds usually skip the full review).

## Notes

- Keep the app generic: no store names or employer branding in the name, icon, screenshots or description.
- Testers' feedback and screenshots come to you through TestFlight. The app itself sends nothing.
