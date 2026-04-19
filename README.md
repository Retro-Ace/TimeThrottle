<p align="center">
  <img src="Assets/timethrottle-banner.png" width="900">
</p>

<h1 align="center">TimeThrottle</h1>

<p align="center">
How much time did speed really buy you?
</p>

**TimeThrottle** is an iPhone Live Drive pace-analysis app.

Apple Maps provides route lookup, autocomplete, route options, and the ETA baseline. TimeThrottle then tracks your real drive and shows:
- Time Above Set Speed
- Time Below Set Speed
- projected arrival versus Apple Maps ETA baseline

TimeThrottle does **not** provide built-in turn-by-turn navigation. During Live Drive it can hand off navigation to Apple Maps, Google Maps, or Waze while TimeThrottle continues tracking the trip.

## What's New in v1.4.3

Use this block for GitHub releases, TestFlight notes, and App Store Connect:

> **TimeThrottle 1.4.3**
>
> - Polished the Current Speed HUD card with a wider Avg Spd pill
> - Updated HUD wording to Apple Maps ETA, Time Above Set Speed, and Time Below Set Speed
> - Clarified Live Drive setup with desired-speed wording and an empty speed-entry prompt
> - Consolidated finished-trip and Trip History detail stats into tighter result summaries
> - Uses destination local time for projected arrival when that time zone is available

## Core Product

### Live Drive

Live Drive is the full product.

It supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default start
- Apple Maps-style address autocomplete
- route options and route preview
- desired-speed entry before the drive starts
- live GPS tracking
- pause, resume, and end trip controls
- a compact in-app Live Drive HUD
- Trip History for completed drives
- shareable finished-trip summaries
- optional navigation handoff to Apple Maps, Google Maps, or Waze

### Live Drive HUD

The Live Drive HUD is a full-screen in-app driving view built from real TimeThrottle trip state.

It shows:
- Current Speed as the hero metric
- Apple Maps ETA as the Apple Maps baseline
- Arrive as projected arrival in the destination's local time when available
- Time Above Set Speed
- Time Below Set Speed
- distance driven
- route/map context
- Pause / Resume and End Trip controls
- a full-width live map with recenter control

The HUD map follows the user during a drive, stops following if the user pans away, and provides a clear recenter control.

## Trip Results

Finished trips focus on the pace story:
- **Time Above Set Speed** = total time spent above the chosen desired speed
- **Time Below Set Speed** = total time spent below the chosen desired speed
- **Overall vs Apple ETA baseline** = the finished trip result against the Apple Maps ETA baseline

## Navigation Handoff

TimeThrottle keeps Apple Maps as the route-planning and ETA-baseline layer.

During Live Drive, users can choose:
- **Apple Maps**
- **Google Maps**
- **Waze**
- **Ask Every Time**

TimeThrottle starts tracking first, then opens the selected navigation app if background-location requirements are met.

## Privacy at a Glance

- No user account is required
- Apple Maps is used for route lookup, autocomplete resolution, route options, and ETA baseline planning
- Live Drive uses iPhone location services when the user enables them
- Completed Live Drive trips are stored locally on-device
- The preferred navigation app choice is stored locally on-device
- Sharing only happens when the user explicitly uses the iOS share sheet

For the full policy, see [privacy-policy.md](/Users/anthonylarosa/SPEED%20APP/privacy-policy.md).

## Tech Overview

- **Platform:** iPhone / iOS only
- **Deployment target:** iOS 17+
- **Bundle ID:** `com.timethrottle.app`
- **Current release:** v1.4.3
- **Current build:** 7
- **Primary app target:** `TimeThrottle.xcodeproj`
- **Primary shared UI:** `Sources/SharedUI/RouteComparisonView.swift`

### Core Components

- `LiveDriveTracker.swift` — Live Drive tracking, permission state, speed, and distance updates
- `TripHistoryStore.swift` — local persistence for completed Live Drive trips
- `TripAnalysisEngine.swift` — live pace and trip summary generation
- `PaceAnalysisMath.swift` — shared target-speed time-delta helper
- `RouteModels.swift` — shared route, lookup, autocomplete, and navigation-provider models
- `LiveDriveHUDView.swift` — compact in-app Live Drive HUD
- `LiveDriveHUDMapView_iOS.swift` — HUD map follow and recenter behavior
- `NavigationHandoffService.swift` — Apple Maps / Google Maps / Waze / Ask Every Time handoff behavior

## Repository Layout

```text
TimeThrottle
├── TimeThrottle.xcodeproj
├── README.md
├── CHANGELOG.md
├── privacy-policy.md
├── Assets.xcassets
├── Resources
├── Sources
│   ├── Core
│   ├── SharedUI
│   └── iOS
├── Tests
├── scripts
└── dist-ios
```

## Build Notes

- Main iOS app scheme: `TimeThrottle`
- Simulator packaging script: `./dist-ios`
- Current packaging path: `dist/iOSSimulator/TimeThrottle.app`
- Generated build outputs live in `build/` and `dist/` and are intentionally git-ignored

## Support

For support or privacy questions, contact: **fixitall329@gmail.com**
