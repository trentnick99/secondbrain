# Installing Second Brain on your iPhone

This project was built in a Linux environment, where iOS apps can't be compiled. **The app has not yet been compiled by Xcode or installed on a device.** The steps below are what you do on a Mac to build it, run the tests and put it on your iPhone. If Xcode reports a compile error on first build, see "If the first build fails" at the bottom.

## What you need

| Item | Notes |
|---|---|
| A Mac | Recent enough to run Xcode 16+ |
| Xcode 16 or later | Xcode 26 recommended. Free from the Mac App Store. |
| An iPhone running iOS 18 or later | The deployment target is iOS 18.0 |
| An Apple ID | Free is enough to install on your own phone; see [SIGNING.md](SIGNING.md) for what a paid membership adds |
| A USB-C / Lightning cable | Needed the first time; Wi-Fi debugging works afterwards |

## 1. Get the project onto your Mac

Unzip `SecondBrain.zip` somewhere convenient, for example `~/Developer/SecondBrain`.

## 2. Configure signing (two values)

Open `Config/Signing.xcconfig` in any text editor or in Xcode:

```
DEVELOPMENT_TEAM = ABCDE12345            ← your Team ID
BASE_BUNDLE_ID = com.yourname.secondbrain ← must be unique to you
```

To find your Team ID, open Xcode › Settings › Accounts, add your Apple ID, select it and look at the Team list. For a paid membership, the ID is also shown at developer.apple.com › Account › Membership. If you use a free account, you can instead choose your "Personal Team" in each target's **Signing & Capabilities** tab and Xcode will fill it in.

The widget's bundle ID (`.widgets`) and the App Group (`group.<BASE_BUNDLE_ID>`) are derived from these two values automatically.

## 3. Open and run

1. Double-click `SecondBrain.xcodeproj`. Xcode resolves the local `SecondBrainCore` package automatically, which takes a few seconds.
2. Choose the **SecondBrain** scheme at the top.
3. Pick a simulator, for example any iPhone, and press **⌘R** to try it.
4. To run on your phone: connect it, unlock it, and tap **Trust**. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode** and restart when asked. Select the phone as the destination and press **⌘R**.
5. The first time with a free account, iPhone may block the app. Go to **Settings › General › VPN & Device Management**, tap your Apple ID and choose **Trust**.

On first launch you'll see a short welcome. It asks for notification permission once (with an explanation first) and lets you add fictional sample data to explore.

## 4. Add the widgets and the capture control

- **Home Screen widget:** long-press the Home Screen, tap **Edit › Add Widget**, search for "Second Brain" and choose Small, Medium or Large.
- **Lock Screen widget:** long-press the Lock Screen, tap **Customize › Lock Screen**, tap the widget area and choose a Second Brain widget.
- **Control Center / Action button:** open Control Center, tap **+ › Add a Control**, and choose "Quick Capture". On iPhone 15 Pro and later, go to **Settings › Action Button › Controls › Quick Capture** for one-press capture.
- **Siri:** say "Add a task to Second Brain". All phrases appear in the Shortcuts app under Second Brain.

## 5. Run the tests

In Xcode, press **⌘U** with the SecondBrain scheme. That runs:

- `SecondBrainCoreTests`: 73 engine tests (parser, classifier, recurrence, planning, notification planner)
- `SecondBrainTests`: SwiftData integration tests (capture → persistence, recurrence, carry-forward, backup round-trip)
- `SecondBrainUITests`: end-to-end workflow on the simulator

From Terminal:

```bash
# Engine tests only — fast, no simulator needed
cd Packages/SecondBrainCore && swift test

# Everything, on a simulator (list names with: xcrun simctl list devices available)
xcodebuild test -project SecondBrain.xcodeproj -scheme SecondBrain \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Testing notifications by hand

1. Settings › Notifications › **Send a test notification**, then lock the phone. It arrives in 5 seconds.
2. Capture "Call the vendor in 2 minutes". Then try each state: leave the app open, background it, lock the phone, and force-quit the app. The reminder arrives in every case because it is scheduled with iOS.
3. Long-press the notification and try **Mark Complete**, **Snooze 15 Minutes** and **Open Task**.
4. Restart the iPhone. Pending reminders survive the restart, because iOS keeps them; nothing depends on the app running.

## 6. Keeping the app installed

- **Free Apple ID:** apps signed this way **expire after 7 days**. Reconnect and press ⌘R again to renew. Your data is kept, because reinstalling over the top preserves it.
- **Paid Apple Developer Program ($99/year):** builds last a year. You can also use **TestFlight**:
  1. In Xcode, choose **Any iOS Device** as the destination, then **Product › Archive**.
  2. In the Organizer, choose **Distribute App › TestFlight & App Store**, then **Upload**.
  3. In App Store Connect, create the app record (first time only), wait for processing, and add yourself as an internal tester.
  4. Install from the TestFlight app on your iPhone. TestFlight builds last 90 days, and updates install like App Store updates.

## If the first build fails

The code was checked as far as possible without Xcode: every Swift file passes the Swift parser, the engine compiles and its tests pass, and the project file was validated. SwiftUI, SwiftData and WidgetKit code, however, can only be type-checked by Xcode. If you see a compile error:

1. Note the file and line in Xcode's Issue navigator (⌘5).
2. Most likely causes are small SDK differences, such as a renamed modifier. Fix-its usually resolve them.
3. If the project itself won't open (very unlikely), install XcodeGen (`brew install xcodegen`) and run `xcodegen generate` in the project folder to regenerate it from `project.yml`.
