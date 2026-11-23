# Apple signing & account requirements

iOS only runs apps that are code-signed. This project uses **Automatic signing**: Xcode creates the certificates, App IDs and provisioning profiles for you once you've set a team. Nothing here bypasses Apple's signing or distribution rules.

## The two settings

All signing input lives in `Config/Signing.xcconfig`:

| Setting | Meaning |
|---|---|
| `DEVELOPMENT_TEAM` | Your 10-character Team ID (or your Personal Team) |
| `BASE_BUNDLE_ID` | A unique reverse-DNS ID, such as `com.yourname.secondbrain` |
| `APP_GROUP_IDENTIFIER` | Derived as `group.$(BASE_BUNDLE_ID)`. Shared by the app and the widget. |

Targets and bundle IDs:

| Target | Bundle ID | Entitlements |
|---|---|---|
| SecondBrain (app) | `$(BASE_BUNDLE_ID)` | App Groups |
| SecondBrainWidgets | `$(BASE_BUNDLE_ID).widgets` | App Groups |
| SecondBrainTests / UITests | `.tests` / `.uitests` | none |

## Free Apple ID vs. paid membership

| Capability | Free (Personal Team) | Apple Developer Program |
|---|---|---|
| Install on your own iPhone with Xcode | ✅ (re-install every 7 days) | ✅ (1-year profiles) |
| App Groups (widgets showing live data) | Usually works with a unique bundle ID; registration is per personal team | ✅ |
| Local notifications, Siri/App Intents, widgets, Face ID, Calendar, speech | ✅ | ✅ |
| iCloud sync (CloudKit) | ❌ | ✅ |
| TestFlight / App Store | ❌ | ✅ |

If Xcode can't register the App Group on a free account, remove the App Groups capability from both targets. The app keeps working with its own private storage. Widgets then show an empty state, because they can no longer read the app's data. Settings › About shows "Widgets data sharing: Unavailable in this build" when that happens.

## Turning on iCloud sync (paid membership)

1. Select the **SecondBrain** target, open **Signing & Capabilities**, click **+ Capability** and add **iCloud**. Tick **CloudKit** and add a container named `iCloud.<your bundle id>`.
2. Click **+ Capability** again, add **Background Modes**, and tick **Remote notifications**. This lets CloudKit push changes.
3. Build and run. In the app, go to **Settings › Data** and turn on **iCloud sync**, then quit and reopen the app.

The data model is already CloudKit-compatible: every field has a default, relationships are optional and there are no unique constraints. If sync can't start, the app falls back to local storage and shows a banner rather than failing. `Config/SecondBrain-iCloud.entitlements.example` shows the resulting entitlements.

## Common signing errors

| Message | Fix |
|---|---|
| "Failed to register bundle identifier" | `BASE_BUNDLE_ID` is taken. Choose a more unique one. |
| "Signing requires a development team" | Set `DEVELOPMENT_TEAM`, or pick a team in Signing & Capabilities |
| "Provisioning profile doesn't include the App Groups entitlement" | Open Signing & Capabilities for both targets and let Xcode refresh. Or remove App Groups (see above). |
| App won't open on iPhone ("Untrusted Developer") | iPhone Settings › General › VPN & Device Management › Trust |
| App stopped opening after a week | Free signing expired. Re-run from Xcode. |
