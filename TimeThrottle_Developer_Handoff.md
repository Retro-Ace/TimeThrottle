# TimeThrottle — Developer Handoff (v1.4)

## Project Summary

TimeThrottle is an **iPhone Live Drive pace-analysis app** built around one question:

> **How much time did speed really buy you?**

It is not a built-in turn-by-turn navigation app.

The app uses **Apple Maps** as the route lookup and ETA-baseline layer. During a real drive, it tracks:
- above-target gain
- below-target loss
- overall result versus Apple ETA

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

## v1.4 State

### Version / build
- **Version:** 1.4
- **Build:** 6

### v1.4 focus
- removed non-Live product paths
- removed old non-Live tradeoff logic
- simplified trip results and Trip History
- improved HUD map follow and recenter behavior

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
- `Sources/Core/TimeThrottleCalculator.swift`
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
- Apple ETA and projected arrival context
- above-target and below-target pace time
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

- current release target: **v1.4 / build 6**
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

TimeThrottle is now a Live Drive-only pace-analysis app. It uses Apple Maps for route lookup and ETA baseline planning, tracks real trips, stores Trip History locally, supports optional external navigation handoff, and focuses the product on pace gain, pace loss, and overall result versus Apple ETA.
