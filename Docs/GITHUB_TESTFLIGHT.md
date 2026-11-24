# Build & install from Windows with GitHub Actions + TestFlight

No Mac needed. GitHub's cloud Macs compile the app, and TestFlight puts it on your iPhone. Everything below is done in a web browser on Windows (or on your phone) and only once.

There are two workflows in `.github/workflows/`:

| Workflow | When it runs | Needs an Apple account? | What it does |
|---|---|---|---|
| **Build & Test** | Every push to `main`, or manually | No | Compiles the app, widget and tests on an iPhone simulator. Runs the 73 engine tests and the SwiftData integration tests. Runs the UI tests when started manually. |
| **TestFlight** | Manually (Actions › TestFlight › Run workflow) | Yes, $99/year Developer Program | Builds a signed release and uploads it to TestFlight |

---

## Step 1 — Join the Apple Developer Program (once)

1. Go to **developer.apple.com/programs/enroll**, or use the **Apple Developer** app on your iPhone.
2. Sign in with your Apple ID and enroll as an **Individual** ($99/year).
3. Approval can take up to a couple of days. You'll get an email.

## Step 2 — Note your Team ID

Go to **developer.apple.com/account** and open **Membership details**. Copy the **Team ID**, which is 10 characters like `AB12CD34EF`.

## Step 3 — Choose your bundle ID

Pick something unique, for example **`com.trentnick99.secondbrain`**. You'll use it in steps 4, 5 and 6. The widget gets `com.trentnick99.secondbrain.widgets`, and the shared App Group is `group.com.trentnick99.secondbrain`.

## Step 4 — Register the identifiers (once)

At **developer.apple.com/account**, open **Certificates, Identifiers & Profiles › Identifiers** and tap the **+** button for each of these:

1. **App Group:** choose *App Groups*, set Description to `Second Brain`, and Identifier to `group.com.trentnick99.secondbrain`.
2. **App ID (the app):** choose *App IDs › App*, set Description to `Second Brain`, choose Bundle ID **Explicit** `com.trentnick99.secondbrain`, and tick **App Groups** under Capabilities. Then choose Continue › Register. Open the new App ID, click **Configure** next to App Groups, tick your group and Save.
3. **App ID (the widget):** do the same with `com.trentnick99.secondbrain.widgets`, App Groups ticked and assigned to the same group.

## Step 5 — Create the app in App Store Connect (once)

1. Go to **appstoreconnect.apple.com › Apps › + › New App**.
2. Fill in:
   - Platform: **iOS**
   - Name: something unique on the App Store, such as `Second Brain for Coaches`. App Store names must be unique. Your Home Screen still shows **Second Brain**.
   - Primary language: English (U.S.)
   - Bundle ID: pick `com.trentnick99.secondbrain` from the list
   - SKU: anything, such as `secondbrain`
   - User Access: **Full Access**
3. Nothing is published. The app stays private to you in TestFlight.

## Step 6 — Create an API key for GitHub (once)

1. In App Store Connect, go to **Users and Access › Integrations › App Store Connect API**. If asked, tap **Request Access** and accept.
2. Under **Team Keys**, tap **+**. Set Name to `GitHub` and Access to **Admin**. Admin is required because each run creates an Apple Distribution certificate and App Store profiles for the app and widget through the API. No Mac and no registered iPhone are needed.
3. Tap **Download** to get the `.p8` file. **You can only download it once.** Keep it somewhere safe, and never put it in the repository.
4. Note the **Key ID**, shown in the list, and the **Issuer ID**, shown above the list.

## Step 7 — Add the secrets to GitHub (once)

In the repository on github.com, go to **Settings › Secrets and variables › Actions**.

**Secrets** tab, then **New repository secret** for each:

| Name | Value |
|---|---|
| `APPLE_TEAM_ID` | Optional — already set to `RP964NS9GM` in `Config/Signing.xcconfig` and the workflow |
| `ASC_KEY_ID` | The Key ID from step 6 |
| `ASC_ISSUER_ID` | The Issuer ID from step 6 |
| `ASC_KEY_P8` | Open the `.p8` file in Notepad and paste **all** of it, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

**Variables** tab (optional): `BUNDLE_ID` overrides the default `com.trentnick99.secondbrain`, which is already set in `Config/Signing.xcconfig` and the workflow.

GitHub encrypts secrets, and they never appear in logs.

## Step 8 — Build and upload

1. On github.com, open the repository's **Actions** tab, then **TestFlight**, then **Run workflow** and **Run**.
2. Wait about 10–20 minutes. A green check means it uploaded. The run's **Summary** shows the build number.
3. Apple processes the build for another 5–30 minutes.

## Step 9 — Install on your iPhone

1. In App Store Connect, open your app and go to **TestFlight › Internal Testing › +**. Create a group (for example "Me") and add yourself.
2. Install **TestFlight** from the App Store on your iPhone and sign in with the same Apple ID.
3. Open the invite (by email, or directly in TestFlight) and tap **Install**.

TestFlight builds last 90 days. Every time you run the TestFlight workflow, a new build appears and TestFlight offers **Update**. Your data is kept between updates.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Run stays *Queued*, then fails with “The job was not acquired by Runner…” | GitHub was out of that kind of cloud Mac. Use **Run workflow** and pick another **Cloud Mac type**, or set a repository variable `MAC_RUNNER` (for example `macos-26`) to change the default. The default is `macos-26-intel`. |
| `Missing repository settings: …` | A secret or the `BUNDLE_ID` variable from step 7 is missing or misspelled |
| `No profiles for '…' were found` / `doesn't include the App Groups entitlement` | Check step 4: both App IDs exist, both have App Groups ticked and assigned to `group.<BUNDLE_ID>` |
| `You haven't been given access to cloud-managed distribution certificates` | The API key must have **Admin** access (step 6). Create a new key with Admin and update the three secrets. |
| `API key check` fails with 401 | The Key ID, Issuer ID and .p8 don't belong together. The workflow already trims spaces and rebuilds a key pasted onto one line; if it still fails, make a new Admin key and update all three secrets. |
| Certificate limit | When Apple's distribution-certificate limit is reached, the workflow revokes its oldest distribution certificates and tries again. Revoking doesn't affect builds already in TestFlight. Profiles named "SecondBrain CI …" are replaced on every run. |
| `No suitable application records were found` | The app record from step 5 is missing, or its bundle ID doesn't match `BUNDLE_ID` |
| `The bundle version must be higher…` | Just run the workflow again. The build number is the run number, which always increases. |
| Compile errors in **Build & Test** | Open the failed run, where the **Summary** lists the errors with file and line. Tell Claude, or paste them, and they'll be fixed. |

## GitHub build minutes

Mac build minutes are limited on private repositories under GitHub's free plan. A Build & Test run takes roughly 10–20 minutes, and so does a TestFlight run. To save minutes, Build & Test skips pushes that only change documentation, and the UI tests run only when you start the workflow manually. Public repositories get free Mac minutes. You can switch visibility in Settings › General › Danger Zone; there are no secrets in the code.
