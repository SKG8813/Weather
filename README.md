# Upslope

A personal iPhone weather app for Stowe and Mt. Mansfield. A lock screen widget shows rain or snow in the next hour. Alerts are silent. Snark is PG-13. See [PLAN.md](PLAN.md) for the full plan.

## What's in the repo

| Folder | What it is |
|---|---|
| `Packages/UpslopeCore` | All the logic: next-hour analysis, alert rules, snark, forecast clients, Mansfield rules, the stowe.com parser. Plain Swift with tests. |
| `App` | The iPhone app (SwiftUI): Now, Radar, Mansfield and Settings tabs, plus a Diagnostics screen |
| `Widgets` | Lock screen and home screen widgets, plus the Live Activity |
| `Shared` | Code used by both the app and the widgets |
| `Config` | Build settings. Your own values go in `Config/Local.xcconfig`, which is never committed |
| `project.yml` | XcodeGen spec that generates `Upslope.xcodeproj` |

## First install (about 10 minutes)

You need a Mac with the latest Xcode and a free Apple ID.

1. **Install XcodeGen** (one time):
   ```sh
   brew install xcodegen
   ```
2. **Clone the repo and switch to the branch:**
   ```sh
   git clone https://github.com/SKG8813/weather.git
   cd weather
   git checkout upslope-v1
   ```
3. **Create your local config:**
   ```sh
   cp Config/Local.example.xcconfig Config/Local.xcconfig
   open -e Config/Local.xcconfig
   ```
   Fill in three values:
   - `BUNDLE_ID_PREFIX`: anything unique, such as `com.stefangrundmann`.
   - `DEVELOPMENT_TEAM`: your Personal Team ID. In Xcode, go to **Settings › Accounts**, add your Apple ID, then choose your Personal Team. If you can't find the 10-character ID, leave it empty and pick the team in step 5.
   - `PIRATE_WEATHER_KEY`: your free key from [pirateweather.net](https://pirateweather.net). Optional; without it the app uses 15-minute data.
4. **Generate and open the project:**
   ```sh
   xcodegen
   open Upslope.xcodeproj
   ```
5. **Set up signing.** In Xcode, select the **Upslope** project, then the **Upslope** target, then **Signing & Capabilities**, and choose your Personal Team. Repeat for the **UpslopeWidgets** target.
6. **Install it.** Plug in your iPhone, select it at the top of the Xcode window, and press **Run** (⌘R).
   - The first time, iOS blocks the app. Go to **Settings › General › VPN & Device Management**, tap your Apple ID, then tap **Trust**.
   - Also turn on **Developer Mode** if iOS asks (**Settings › Privacy & Security › Developer Mode**).
7. **In the app,** allow notifications (they're always silent) and location. Then go to **Settings › Allow "Always"** so alerts follow you.
8. **Run Diagnostics.** Go to **Settings › Diagnostics**, wait for the checks to finish, and screenshot the results for Claude. If the stowe.com check fails, tap **Share the stowe.com page Upslope saw** and send that too.
9. **Add the widgets.** Long-press the lock screen, tap **Customize › Lock Screen**, then tap the widget area and add **Upslope**. Long-press a widget to choose *Current location* or *Stowe*.

### If Xcode complains about the App Group
Free Apple IDs sometimes can't use App Groups. If signing fails with an App Group error, delete both `com.apple.security.application-groups` blocks from `project.yml` and run `xcodegen` again. The widgets still work; they fetch their own data instead of sharing the app's.

## The 7-day re-sign

Apps signed with a free Apple ID stop opening after 7 days. Either:
- **Re-run from Xcode** once a week (plug in the phone and press ⌘R), or
- **Use SideStore or AltStore** to refresh it automatically. Setup instructions are coming in phase 9.

## Updating to a new version

```sh
git pull
xcodegen
```
Then press ⌘R in Xcode.

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
