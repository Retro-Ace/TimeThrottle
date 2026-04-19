# TimeThrottle — Developer Handoff (v1.4.3)

## Project Summary

TimeThrottle is an **iPhone Live Drive pace-analysis app** built around one question:

> **How much time did speed really buy you?**

It is not a built-in turn-by-turn navigation app.

The app uses **Apple Maps** as the route lookup and ETA-baseline layer. During a real drive, it tracks:
- Time Above Set Speed
- Time Below Set Speed
- projected arrival versus the Apple Maps ETA baseline

## Current Product Direction

### Live Drive only

The active iPhone product is now **Live Drive-only**.

Supports:
- Apple Maps route lookup + ETA baseline
- Current Location default start
- Apple Maps autocomplete
- route selection and preview
- live GPS tracking
- pause / resume / end trip
- compact in-app HUD
- Trip History
- finished-trip sharing
- optional Apple Maps / Google Maps / Waze handoff

## v1.4.3 State

### Version / build
- **Version:** 1.4.3
- **Build:** 7

### v1.4.3 focus
- polished the Current Speed HUD card and widened the Avg Spd pill
- updated wording to Apple Maps ETA, Time Above Set Speed, and Time Below Set Speed
- clarified Live Drive setup around desired speed
- consolidated finished-trip and Trip History detail stats
- kept HUD map follow and recenter behavior intact

## Important product truth constraints

Do not imply:
- built-in turn-by-turn navigation
- lane guidance
- road speed-limit ownership
- live traffic ownership

TimeThrottle can safely show:
- route context
- Apple ETA baseline
- projected arrival
- pace analysis
- optional external navigation handoff

## Most Important Current Files

### Core
- `Sources/Core/LiveDriveTracker.swift`
- `Sources/Core/TripAnalysisEngine.swift`
- `Sources/Core/PaceAnalysisMath.swift`
- `Sources/Core/TripHistoryStore.swift`

### Shared UI
- `Sources/SharedUI/RouteComparisonView.swift`
- `Sources/SharedUI/RouteModels.swift`
- `Sources/SharedUI/NavigationHandoffService.swift`
- `Sources/SharedUI/TripHistoryViews.swift`
- `Sources/SharedUI/LiveDriveHUDView.swift`

### iOS
- `Sources/iOS/TimeThrottleApp_iOS.swift`
- `Sources/iOS/IOSRouteComparisonScreen.swift`
- `Sources/iOS/RoutePreviewMapView_iOS.swift`
- `Sources/iOS/LiveDriveHUDMapView_iOS.swift`

## Current HUD Notes

### Current HUD intent
- more glanceable than the normal active Live Drive screen
- current speed as the hero metric
- compact route/address footprint
- easier access to Pause / Resume / End Trip
- Apple Maps ETA and projected arrival context
- Time Above Set Speed and Time Below Set Speed
- lower map context without pretending to be full navigation

### Current HUD map behavior
- follows the user by default
- stops following on manual pan
- exposes a recenter control
- returns to follow mode when recentered
- keeps a stable driving zoom instead of constantly re-fitting

## Current Repo Structure

```text
SPEED APP
├── Assets.xcassets
├── build
├── dist
├── Resources
├── scripts
├── Sources
│   ├── Core
│   ├── iOS
│   └── SharedUI
├── Tests
├── CHANGELOG.md
├── privacy-policy.md
├── README.md
├── Package.swift
├── TimeThrottle.xcodeproj
└── dist-ios
```

## Release / Packaging Notes

- current release target: **v1.4.3 / build 7**
- simulator build path: `./dist-ios`
- current simulator bundle output: `dist/iOSSimulator/TimeThrottle.app`

## Important “Do Not Break” List

Protect:
- Apple Maps route lookup
- Apple ETA baseline
- Live Drive trip tracking
- finished-trip flow
- Trip History
- truthful navigation positioning
- HUD auto-open / close / reopen behavior
- pause / resume / end trip behavior

## Final Plain-English Summary

TimeThrottle is now a Live Drive-only pace-analysis app. It uses Apple Maps for route lookup and ETA baseline planning, tracks real trips, stores Trip History locally, supports optional external navigation handoff, and focuses the product on Time Above Set Speed, Time Below Set Speed, and projected arrival versus Apple Maps ETA baseline.
