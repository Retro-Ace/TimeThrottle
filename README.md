<p align="center">
  <img src="Assets/timethrottle-banner.png" width="900">
</p>

<h1 align="center">TimeThrottle</h1>

<p align="center">
How much time did speed really buy you?
</p>

**TimeThrottle** is an iPhone Live Drive pace-analysis app.

Apple Maps provides route lookup, autocomplete, route options, and the ETA baseline. TimeThrottle then tracks your real drive and shows:
- pace gain
- pace loss
- overall result versus Apple ETA

TimeThrottle does **not** provide built-in turn-by-turn navigation. During Live Drive it can hand off navigation to Apple Maps, Google Maps, or Waze while TimeThrottle continues tracking the trip.

## What's New in v1.4

Use this block for GitHub releases, TestFlight notes, and App Store Connect:

> **TimeThrottle 1.4**
>
> - Simplified the app to focus on Live Drive
> - Removed extra planning inputs and old tradeoff assumptions
> - Improved Live Drive HUD with real-time map tracking and recenter behavior
> - Cleaner trip results focused on pace versus Apple ETA

## Core Product

### Live Drive

Live Drive is the full product.

It supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default start
- Apple Maps-style address autocomplete
- route options and route preview
- live GPS tracking
- pause, resume, and end trip controls
- a compact in-app Live Drive HUD
- Trip History for completed drives
- shareable finished-trip summaries
- optional navigation handoff to Apple Maps, Google Maps, or Waze

### Live Drive HUD

The Live Drive HUD is a full-screen in-app driving view built from real TimeThrottle trip state.

It shows:
- current speed
- trip status and elapsed time
- Apple ETA baseline
- projected arrival
- time above target speed
- time below target speed
- distance driven
- route/map context
- Pause / Resume and End Trip controls

The HUD map follows the user during a drive, stops following if the user pans away, and provides a clear recenter control.

## Trip Results

Finished trips focus on the pace story:
- **Above-target gain** = time gained while driving above your target pace
- **Below-target loss** = time lost while driving below your target pace
- **Overall vs Apple ETA** = the finished trip result against the Apple Maps ETA baseline

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
- **Current release:** v1.4
- **Current build:** 6
- **Primary app target:** `TimeThrottle.xcodeproj`
- **Primary shared UI:** `Sources/SharedUI/RouteComparisonView.swift`

### Core Components

- `LiveDriveTracker.swift` — Live Drive tracking, permission state, speed, and distance updates
- `TripHistoryStore.swift` — local persistence for completed Live Drive trips
- `TripAnalysisEngine.swift` — live pace and trip summary generation
- `TimeThrottleCalculator.swift` — shared target-pace time-delta helper
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
