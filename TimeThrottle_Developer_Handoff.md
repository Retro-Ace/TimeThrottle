# TimeThrottle — Developer Handoff (v2.0)

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

The active iPhone product is **Live Drive** with route intelligence layered on top of the Apple Maps route baseline, plus a separate **Scanner** tab for informational public scanner listening.

Supports:
- Apple Maps route lookup + ETA baseline
- Current Location default start
- Apple Maps autocomplete
- route selection and preview
- live GPS tracking
- pause / resume / end trip
- Map tab active driving HUD
- floating Map recenter control
- compact floating weather chip when route forecast data is available
- compact nearest-aircraft Map bar when aircraft data exists
- route-step guidance in the Map tab
- bottom navigation for Drive, Map, Trips, and Scanner
- Scanner Nearby / Browse public scanner systems
- OpenMHz-style scanner systems, latest calls, and talkgroups client
- scanner playback with background audio while playback is active
- dedicated map-first active driving view
- improved local iOS system voice guidance with persisted voice settings
- Map tab Options panel for weather, aircraft, enforcement alerts, voice, speed-limit, pace, map mode, average speed, and top speed details
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

## v2.0 State

### Version / build
- **Version:** 2.0
- **Build:** 22

- adds the Scanner tab as a separate listening-only feature
- supports Nearby and Browse scanner systems
- loads latest public scanner calls for a selected system
- adds scanner selected/latest-call play / pause / next-call playback and background audio support
- adds build 21 real-device fixes for Scanner audio-session fallback diagnostics, aircraft marker visibility, and OpenStreetMap Overpass-backed enforcement/camera source and marker diagnostics
- adds build 22 Enforcement Alerts capping so route-active results are limited to 35 visible alerts within 3.5 miles and no-route results are limited to 25 nearby alerts within 3.0 miles
- keeps route intelligence details in Map Options
- keeps Live Drive tracking, Apple Maps ETA baseline, speed-limit analysis, route intelligence, Trip History, and external handoff intact

## Important product truth constraints

Do not imply:
- Apple-native turn-by-turn navigation
- lane guidance
- certified speed-limit accuracy
- live traffic ownership
- aviation safety or collision-avoidance alerts
- certain enforcement detection
- scanner audio recording
- scanner-based route warnings, incident prediction, or driving recommendations

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
- public scanner listening when the user opens Scanner
- background scanner audio after the user starts playback
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
- `Sources/Core/ScannerModels.swift`
- `Sources/Core/OpenMHzScannerService.swift`

### Shared UI
- `Sources/SharedUI/RouteComparisonView.swift`
- `Sources/SharedUI/RouteModels.swift`
- `Sources/SharedUI/NavigationHandoffService.swift`
- `Sources/SharedUI/TripHistoryViews.swift`
- `Sources/SharedUI/LiveDriveHUDView.swift`
- `Sources/SharedUI/ScannerViewModel.swift`
- `Sources/SharedUI/ScannerTabView.swift`

### iOS
- `Sources/iOS/TimeThrottleApp_iOS.swift`
- `Sources/iOS/IOSRouteComparisonScreen.swift`
- `Sources/iOS/RoutePreviewMapView_iOS.swift`
- `Sources/iOS/LiveDriveHUDMapView_iOS.swift`

## Current Map HUD Notes

### Current Map intent
- map-first active driving context
- direct access to Pause / Resume / End Trip
- Apple Maps ETA and projected arrival context
- Time Above Speed Limit and Time Below Speed Limit
- Top speed where valid GPS speed data exists
- route polyline and current location without pretending to be full navigation
- guidance based on Apple Maps route steps
- local system voice guidance controls
- Speed Limit estimate / Unavailable state
- optional Nearby Low Aircraft marker layer
- optional passive Enforcement Alerts marker layer when enabled and data is available

## Current App Navigation

- **Drive:** Live Drive setup, Current Location start, destination input, route options, compact navigation app choice, and Start Drive.
- **Map:** primary active driving HUD with route polyline, user location, next maneuver, speed, Speed Limit estimate where available, Apple Maps ETA, projected arrival, route distance, miles driven, Pause / Resume, End Trip, recenter, and Options.
- **Trips:** Trip History list and details.
- **Scanner:** Nearby / Browse public scanner systems, selected-system latest calls, and playback.

Switching tabs should not reset active trip state.

### Current Map behavior
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

- current release target: **v2.0 / build 22**
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
- Map tab active-drive controls and Options behavior
- pause / resume / end trip behavior

## Final Plain-English Summary

TimeThrottle is now a Live Drive-first pace-analysis app with bottom navigation. It uses Apple Maps for route lookup and ETA baseline planning, tracks real trips, stores Trip History locally, supports optional external navigation handoff, and focuses driving results on Time Above Speed Limit, Time Below Speed Limit, and projected arrival versus Apple Maps ETA baseline.
TimeThrottle 2.0 keeps speed-limit analysis tied to available OpenStreetMap estimates, keeps optional OpenStreetMap Overpass-backed Enforcement Alerts carefully worded, keeps Standard / Satellite map mode, uses Drive / Map / Trips / Scanner with Scanner as a separate public listening tab, and keeps Map route-intelligence details in Options without adding unsupported navigation, enforcement, weather, speed-limit, scanner, or safety claims.
