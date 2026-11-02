# Upslope

A personal iPhone weather app for Stowe and Mt. Mansfield. A lock screen widget shows rain or snow in the next hour. Alerts are silent. Snark is PG-13. See [PLAN.md](PLAN.md) for the full plan.

## What's in the repo

| Folder | What it is |
|---|---|
| `Packages/UpslopeCore` | All the logic: next-hour analysis, alert rules, snark, forecast clients, Mansfield rules, the stowe.com parser. Plain Swift with tests. |
| `App` | The iPhone app (SwiftUI): Now, Radar, Mansfield and Settings tabs, plus a Diagnostics screen |
| `Widgets` | Lock screen and home screen widgets, plus the Live Activity |
| `Shared` | Code used by both the app and the widgets |
| `Config` | Build settings. Optional developer overrides go in `Config/Local.xcconfig`, which is never committed |
| `Upslope.xcodeproj` | The Xcode project. Generated from `project.yml` with XcodeGen and committed, so you don't need XcodeGen |

## First install (no Terminal needed)

You need a Mac, an iPhone with its cable, and your Apple ID. Plan on about 30 minutes, most of it the Xcode download.

### 1. Install Xcode
Open the **App Store** on your Mac, search for **Xcode**, and install it. It's free but large. Open it once when it finishes, accept the agreement, and if it asks which platforms to install, make sure **iOS** is checked.

### 2. Download the app's code
1. On github.com, open **SKG8813/Weather**.
2. Click the branch menu (it says **main**) and choose **upslope-v1**.
3. Click the green **Code** button, then **Download ZIP**.
4. Double-click the ZIP in your Downloads folder to unzip it.

### 3. Open the project
In the unzipped folder, double-click **Upslope.xcodeproj**. Xcode opens it and spends a minute fetching packages.

### 4. Sign in and choose your team
1. In Xcode's menu bar, choose **Xcode › Settings › Accounts** (called *Apple Accounts* in some versions). Click **+** and sign in with your Apple ID.
2. Close Settings. In the left sidebar, click the blue **Upslope** project icon at the top.
3. Under **Targets**, select **Upslope**, then open the **Signing & Capabilities** tab. Set **Team** to *(your name) (Personal Team)*.
4. Select the **UpslopeWidgets** target and set the same Team.

If you see a red error mentioning **App Groups**, click the small trash icon next to **App Groups** on that tab, for both targets. The widgets still work without it.

### 5. Get your iPhone ready
1. Plug the iPhone into the Mac. On the phone, tap **Trust** and enter your passcode.
2. On the iPhone, open **Settings › Privacy & Security › Developer Mode**, turn it on, and let the phone restart. (The switch appears only after the phone has been plugged into Xcode once.)

### 6. Install the app
1. At the top of the Xcode window, click the device menu and pick your iPhone.
2. Press the **▶︎ Run** button (or ⌘R). The first build takes a few minutes.
3. The first time, iOS blocks the app. On the iPhone, go to **Settings › General › VPN & Device Management**, tap your Apple ID, then tap **Trust**. Press Run again.

### 7. Set it up on the phone
1. Allow notifications (they're always silent) and location.
2. In the app, go to **Settings**:
   - Tap **Allow "Always"** so alerts follow you.
   - Paste your free Pirate Weather key from [pirateweather.net](https://pirateweather.net) and tap **Save key**. Optional; without it you get 15-minute data.
3. Open **Settings › Diagnostics**, wait for the checks to finish, and screenshot the results for Claude. If the stowe.com check fails, tap **Share the stowe.com page Upslope saw** and send that too.
4. Add the widget: long-press the lock screen, tap **Customize › Lock Screen**, tap the widget area, and add **Upslope**. Tap the widget to choose *Current location* or *Stowe*.

## The 7-day re-sign

Apps signed with a free Apple ID stop opening after 7 days. Plug in the phone and press **Run** in Xcode again. Automatic re-signing is coming later.

## Updating to a new version

Download the ZIP again (step 2), open the new **Upslope.xcodeproj**, set the Team again (step 4), and press Run.

## Development

- **Core tests:** `cd Packages/UpslopeCore && swift test`. They also run on Linux.
- **CI:** GitHub Actions runs the core tests and an unsigned iOS Simulator build on every push (`.github/workflows/build.yml`).

## Data sources

- **Pirate Weather:** minute-by-minute next hour
- **Open-Meteo:** 7-day, Mansfield elevations, backup next hour
- **NWS Burlington:** forecast discussion
- **stowe.com:** terrain and lift status. Unofficial; read rarely, for personal use.
- **Iowa Environmental Mesonet:** NEXRAD radar tiles

The fonts are Barlow and Barlow Condensed (SIL Open Font License, see `App/Fonts/OFL.txt`).
