# Upslope: build plan (v1)

A personal iPhone weather app for Stowe and Mt. Mansfield. A lock screen widget shows rain or snow in the next hour. Silent alerts warn you before it starts. A Mansfield tab covers ski conditions. It's free to build and run, uses the Trail Map design in the Spruce & Signal colors, and has PG-13 snark.

Status: **draft for approval.** No code has been written yet.

---

## 1. Scope

### In version 1
| Feature | Notes |
|---|---|
| Next-hour rain and snow | Start time, duration, intensity (light, moderate or heavy, plus inches per hour), total, and type (rain, snow or mix) |
| Lock screen widgets | Rectangular (bars and numbers), circular (countdown), inline (one line above the clock) |
| Home screen widgets | Small and medium, in color |
| Silent alerts | For any precipitation in the next hour. No sound. One alert per event, replaced if the forecast shifts |
| Locations | "Here" (follows the phone, works anywhere on the East Coast and beyond) and "Stowe" (fixed) |
| 7-day forecast | Highs and lows, chance of rain or snow, amounts, icons |
| Mansfield tab | Upper mountain vs. base forecast, snow line, upslope signal, wind-hold risk, 7-day upper-mountain snow, NWS Burlington forecast discussion |
| Resort report | Read from stowe.com: % open, trails and lifts open, new snow, base depth (upper and lower), open/closed status for **Upper National, Goat and Starr Glades** (no difficulty markings), silent "tell me when it opens" alerts |
| Radar tab | Animated precipitation radar map |
| Snark | PG-13. Varies by type, intensity and trail. Can be turned down in Settings |

### Only if a capability check passes (see Risks)
- **Live Activity and Dynamic Island countdown,** started from a "Track this storm" button.

### Not in version 1
- Push alerts sent from a server (needs the $99/yr Apple account)
- Apple WeatherKit data (needs the $99/yr account)
- Any locations beyond "Here" and Stowe
- An Apple Watch app

---

## 2. Architecture

```
┌──────────────────────────── iPhone ─────────────────────────────┐
│  Upslope app (SwiftUI)                                          │
│   ├─ Now · Radar · Mansfield · Settings                         │
│   └─ Background refresh + location-change wakeups               │
│            │ writes latest forecast + alert state               │
│            ▼                                                    │
│   Shared storage (App Group)  ◄────── reads ──────┐             │
│            ▲                                      │             │
│  Widget extension (WidgetKit)                     │             │
│   ├─ lock screen: rectangular / circular / inline │             │
│   └─ home screen: small / medium                  │             │
│  (Live Activity, if available)                    │             │
│                                                   │             │
│  UpslopeCore (shared Swift package) ──────────────┘             │
│   forecast clients · next-hour analyzer · intensity rules ·     │
│   Mansfield heuristics · resort report parser · snark engine    │
└─────────────────────────────────────────────────────────────────┘
        │ HTTPS (no server of our own)
        ▼
  Pirate Weather · Open-Meteo · NWS API · stowe.com · radar tiles
```

- **No backend, nothing to host, $0 to run.**
- **UpslopeCore** holds all the logic as plain Swift with unit tests. The app and the widget both use it, so they always agree.
- **The widget fetches data itself** when iOS refreshes it, roughly every 15 to 30 minutes, which iOS controls. Between refreshes, countdowns tick live on their own.
- **The app checks in the background** (when iOS allows it) and when you move about 500 m or more. If precipitation is coming, it posts or replaces the silent alert and refreshes the widgets.
- **Xcode project:** I'll generate it with **XcodeGen** from a `project.yml` file, because I can't run Xcode from here. You run one command on your Mac to create the `.xcodeproj`.

---

## 3. Data sources (all free)

| Need | Source | Notes / limits |
|---|---|---|
| Next hour, minute by minute | **Pirate Weather** (primary) | Free API key you sign up for yourself. The free tier is roughly 10k calls a month (to verify), which covers 2 locations every ~15 min. The key stays in a local file that is never committed. |
| Next hour, backup | **Open-Meteo** `minutely_15` | No key needed. 15-minute steps from NOAA's HRRR model in the US. Used if Pirate Weather fails. |
| 7-day, hourly | **Open-Meteo** | Highs and lows, chances, rain and snowfall amounts, freezing level, upper-air winds |
| Mansfield upper vs. base | **Open-Meteo** with the `elevation` setting | Separate forecasts for about 3,600′ (upper mountain) and about 1,560′ (Mansfield base). Exact elevations and coordinates to be confirmed. |
| Forecaster's take | **NWS API**: Burlington forecast discussion | Free, no key |
| Resort report | **stowe.com** terrain and lift status page | No official API. See Risks. |
| Radar | **RainViewer** map tiles, or the Iowa State Mesonet NEXRAD tiles as fallback | Free. Exact provider confirmed in phase 7. |

### Rules (our own definitions, shown in the app)
- **Rain intensity:** light < 0.1″/hr, moderate 0.1–0.3″/hr, heavy > 0.3″/hr. Shown as trail signs: green circle, blue square, black diamond.
- **Snow intensity:** light < 0.5″/hr, moderate 0.5–1″/hr, heavy > 1″/hr.
- **When to alert:** precipitation probability ≥ 50% and above a trace for 3 or more consecutive minutes within 60 minutes.
- **One alert per event:** the alert is replaced (not repeated) if the start time moves more than 5 minutes or the type changes. A new event needs 30 or more dry minutes first.
- **Snow line:** roughly the freezing level minus about 1,000′.
- **Upslope signal:** northwest wind (270–340°) of at least 15 mph at about 5,000′, with sub-freezing temperatures and moist air. Rated none, moderate or strong.
- **Wind-hold risk:** upper-mountain gusts ≥ 40 mph means elevated; ≥ 50 mph means high. Always labelled "our guess, not the resort's."
- **All alerts are silent.** No sound or vibration, ever.

---

## 4. Brand spec: Trail Map in Spruce & Signal

| Token | Value |
|---|---|
| Background | `#0E2620` |
| Surface | `#173A30` |
| Line | `#2B5446` |
| Text / soft / muted | `#F1F6F2` / `#D3E3DA` / `#A2BFB2` |
| Accent (signal yellow) | `#F2C230`, with text on it in `#0E2620` |
| Snow / rain / mix icons | `#CFE8FF` / `#8CC3FF` / `#D8C9FF` |

- **Type:** Barlow Condensed for headings and numbers, Barlow for body text. Both are bundled in the app under the free SIL Open Font License.
- **Intensity:** the trail-sign shapes, which still read in the single-color lock screen widgets. Used only for precipitation intensity, never to mark trail difficulty.
- **App icon:** the Mansfield ridge with a snowcap in signal yellow on spruce green.
- **Snark:** PG-13, short, never mean about the user. Separate line pools by type, intensity, time of day and trail. Three levels in Settings: mild, standard, unhinged.

---

## 5. Screens and widget states

**App tabs:**
- **Now:** Here/Stowe toggle, headline, snark, 60-minute chart, starts/lasts/peak/total, current conditions, 7-day forecast
- **Radar**
- **Mansfield:** profile drawing with snow line, 24h upper vs. base snow, resort report, your trails, upper and base conditions, upslope and wind-hold, 7-day snow, NWS forecast discussion
- **Settings:** locations, snark level, trail watch list, data-source credits

**Target device:** iPhone 18 Pro (Dynamic Island) on the latest iOS. The minimum iOS version is set to whatever your Xcode ships with; confirmed in phase 0.

**Every widget handles these states:** dry · starting soon · happening now · on and off · data is old ("as of 10:42") · no location permission · fetch failed.

---

## 6. Build phases

| # | Phase | What I deliver | What you test on your phone |
|---|---|---|---|
| 0 | **Capability check** | A tiny test app: widget plus shared storage, background refresh, location wakeups, a Live Activity attempt, and a stowe.com fetch | Install it with your free Apple ID and tell me which checks pass |
| 1 | **Core logic** | UpslopeCore: forecast clients, next-hour analyzer, intensity rules, 7-day, snark engine, plus unit tests | Nothing yet. Tests run on the Mac with `swift test` |
| 2 | **App and Now screen** | App shell, theme, Now tab, 7-day, Here/Stowe, Settings | Real forecasts, layout on your phone |
| 3 | **Widgets** | Lock rectangular, circular, inline; home small and medium; refresh timing | Add the widgets and watch them through a storm |
| 4 | **Background and silent alerts** | Background refresh, location wakeups, alert rules, one-alert-per-event | Silent banners: timing, no sound, no duplicates |
| 5 | **Mansfield** | Elevation forecasts, snow line, upslope, wind-hold, NWS discussion | Compare with what you actually see on the mountain |
| 6 | **Resort report** | stowe.com parser, watch list (Upper National, Goat, Starr Glades), "opens" alerts | Check against the official report |
| 7 | **Radar** | Animated radar map | |
| 8 | **Live Activity** (only if phase 0 passes) | "Track this storm" button, lock screen card, Dynamic Island | |
| 9 | **Polish and install guide** | Icon, fonts, empty and error states, install and 7-day re-signing guide for you and friends | Full run-through |

**Workflow:**
- Each phase goes on a branch in `skg8813/weather` with small commits.
- No pull requests unless you ask for one.
- I'll run the core tests here if a Swift toolchain is available. Everything that needs iOS gets built and tested by you in Xcode.

---

## 7. Risks and open items

1. **Live Activities probably need the paid account.** Developer reports say free accounts don't get the ActivityKit entitlement. Phase 0 checks this. If it fails, it moves to the "$99 later" list, and the widget's live countdown covers most of the need.
2. **stowe.com blocks automated requests.** A test fetch from this cloud environment got an error page; it may work from your phone. There's no official API, and reading the page may conflict with Vail Resorts' terms of use. The parser will break whenever they redesign the site. For personal use I'll keep requests rare (about every 30 minutes, only in season). If it doesn't work from the phone, the fallback is a "View Stowe report" button that opens the page.
3. **Background timing is up to iOS.** Alerts, including "trail opened" alerts, are best-effort and can arrive late.
4. **Free Apple ID limits:** the app expires every 7 days (AltStore or SideStore re-signs it automatically), and you can have at most 3 sideloaded apps. Phase 0 also confirms that widgets and shared storage work under a free account.
5. **Pirate Weather free-tier limits** need checking. Friends would each need their own key, or we accept sharing yours inside the app.
6. **Model forecasts are not the resort's official snow report.** The app says so wherever it matters.

---

## 8. Install guide (outline, written in phase 9)
1. On your Mac: install Xcode and XcodeGen, then clone the repo.
2. Sign up for a free Pirate Weather key and put it in your local `Secrets.xcconfig`.
3. Run `xcodegen`, open the project, and sign in with your Apple ID (free).
4. Run the app on your iPhone. Trust the developer profile in Settings.
5. Set up automatic weekly re-signing (AltStore or SideStore).
6. Add the lock screen and home screen widgets.
7. For friends: the same steps with their own Apple ID.
