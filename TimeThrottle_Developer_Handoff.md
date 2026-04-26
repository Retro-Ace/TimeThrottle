# TimeThrottle — Developer Handoff (v1.5.5)

> Start here when you want the shortest practical handoff.
>
> - Read `README.md` first if you are new to the repo.
> - Use this file for quick current-state, version, and product-direction context.
> - Read `TimeThrottle_Master_Project_Doc.md` if you need a fuller reference document.

## Project Summary

TimeThrottle is an **iPhone Live Drive pace-analysis app** built around one question:

> **How much time did speed really buy you?**

It is not an Apple Maps replacement or Apple-native navigation engine.

The app uses **Apple Maps** as the route lookup and ETA-baseline layer. During a real drive, it tracks:
- Time Above Speed Limit
- Time Below Speed Limit
- projected arrival versus the Apple Maps ETA baseline
- route-step guidance based on Apple Maps route data

## Current Product Direction

### Live Drive with route intelligence

The active iPhone product is **Live Drive** with route intelligence layered on top of the Apple Maps route baseline.

Supports:
- Apple Maps route lookup + ETA baseline
- Current Location default start
- Apple Maps autocomplete
- route selection and preview
- live GPS tracking
- pause / resume / end trip
- compact in-app HUD
- route-step guidance in the HUD
- bottom navigation for Drive, HUD, Map, and Trips
- dedicated map-first route view
- improved local iOS system voice guidance with persisted voice settings
- Map tab Options panel for weather, aircraft, voice, speed-limit, and pace details
- optional Enforcement Alerts foundation with provider-backed/empty-state behavior
- Standard / Satellite map mode with local persistence
- Top speed tracking for completed trips
- route weather checkpoints
- speed-limit estimates where OpenStreetMap data is available, with local cache support
- optional passive Nearby Low Aircraft from OpenSky ADS-B data with conservative refresh and stale cleanup
- optional passive Enforcement Alerts when a configured camera/enforcement source is available
- Standard / Satellite map mode
- Top speed on new completed trips when valid GPS speed data exists
- Trip History
- finished-trip sharing
- optional Apple Maps / Google Maps / Waze handoff

## v1.5.5 State

### Version / build
- **Version:** 1.5.5
- **Build:** 13

### v1.5.5 focus
- adds optional, passive Enforcement Alerts for configured speed-camera, red-light-camera, and enforcement-report providers
- adds Standard / Satellite map mode selection with local persistence
- tracks Top speed from valid GPS speed samples and persists it on new completed trips
- simplifies Drive setup to Current Location start plus destination and replaces the large navigation-app list with a compact selector
- keeps Live Drive tracking, Apple Maps ETA baseline, speed-limit analysis, route intelligence, Trip History, and external handoff intact

## Important product truth constraints

Do not imply:
- Apple-native turn-by-turn navigation
- lane guidance
- certified speed-limit accuracy
- live traffic ownership
- aviation safety or collision-avoidance alerts
- guaranteed enforcement or police detection

TimeThrottle can safely show:
- route context
- guidance based on Apple Maps route steps
- Apple ETA baseline
- projected arrival
- pace analysis
- route weather forecast near route checkpoints
- speed-limit estimates where available
- optional passive nearby low ADS-B aircraft
- optional provider-backed camera/enforcement alerts with region-dependent coverage and quiet empty/unavailable states
- optional external navigation handoff

## Most Important Current Files

### Core
- `Sources/Core/LiveDriveTracker.swift`
- `Sources/Core/TripAnalysisEngine.swift`
- `Sources/Core/PaceAnalysisMath.swift`
- `Sources/Core/TripHistoryStore.swift`
- `Sources/Core/TurnByTurnGuidanceEngine.swift`
- `Sources/Core/VoiceGuidanceSettings.swift`
- `Sources/Core/WeatherRouteProvider.swift`
- `Sources/Core/SpeedLimitProvider.swift`
- `Sources/Core/OSMSpeedLimitService.swift`
- `Sources/Core/OSMSpeedLimitProvider.swift`
- `Sources/Core/AircraftProvider.swift`
- `Sources/Core/OpenSkyAircraftProvider.swift`
- `Sources/Core/EnforcementAlertProvider.swift`

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
- Time Above Speed Limit and Time Below Speed Limit
- Top speed where valid GPS speed data exists
- lower map context without pretending to be full navigation
- guidance based on Apple Maps route steps
- local system voice guidance controls
- Speed Limit estimate / Unavailable state
- optional Nearby Low Aircraft marker layer
- optional passive Enforcement Alerts marker layer when enabled and data is available

## Current App Navigation

- **Drive:** Live Drive setup, Current Location start, destination input, route options, compact navigation app choice, and Start Drive.
- **HUD:** focused active driving dashboard, or an empty state when no trip is active.
- **Map:** larger map-first route view with route polyline, user location, next maneuver, speed, Speed Limit estimate where available, recenter support, and an Options panel for details.
- **Trips:** Trip History list and details.

Switching tabs should not reset active trip state.

### Current HUD map behavior
- follows the user by default
- stops following on manual pan
- exposes a recenter control
- returns to follow mode when recentered
- keeps a stable driving zoom instead of constantly re-fitting

## Current Repo Structure

```text
TimeThrottle
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

- current release target: **v1.5.5 / build 13**
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
- HUD tab / close / reopen behavior
- pause / resume / end trip behavior

## Final Plain-English Summary

TimeThrottle is now a Live Drive-only pace-analysis app with bottom navigation. It uses Apple Maps for route lookup and ETA baseline planning, tracks real trips, stores Trip History locally, supports optional external navigation handoff, and focuses the product on Time Above Speed Limit, Time Below Speed Limit, and projected arrival versus Apple Maps ETA baseline.
TimeThrottle 1.5.5 keeps speed-limit analysis tied to available OpenStreetMap estimates, adds optional provider-backed Enforcement Alerts with careful wording, adds Standard / Satellite map mode, persists Top speed on new trip records, simplifies Drive setup, and keeps route intelligence organized without adding unsupported navigation, enforcement, or safety claims.
