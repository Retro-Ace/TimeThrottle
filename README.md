<p align="center">
  <img src="Assets/timethrottle-banner.jpg" width="900">
</p>

<h1 align="center">TimeThrottle</h1>

<p align="center">
How much time did speed really buy you?
</p>

> Start here if you are new to this repo.
>
> - This repo is the standalone TimeThrottle codebase only.
> - Read this file for the product overview, current release, privacy summary, and build notes.
> - Read `CHANGELOG.md` for release history.
> - Read `privacy-policy.md` for the public privacy policy.

**TimeThrottle** is an iPhone Live Drive pace-analysis app.

Apple Maps provides route lookup, autocomplete, route options, and the ETA baseline. TimeThrottle then tracks your real drive and shows:
- Time Above Speed Limit
- Time Below Speed Limit
- projected arrival versus Apple Maps ETA baseline

TimeThrottle now adds in-app guidance and route intelligence on top of the Apple Maps route data. It is not an Apple Maps replacement: external handoff to Apple Maps, Google Maps, or Waze remains available while TimeThrottle continues tracking the trip.

## What's New in v2.0

Build 26 moves TimeThrottle to a map-first shell:
- the app opens directly to the full-screen map with no former four-tab navigation bar
- route setup now lives in an Apple Maps-style bottom panel over the map
- idle map actions are Choose Route, Log Trip, and Menu
- Trip History and Scanner open from Menu sheets while Scanner stays independent from Live Drive
- the TimeThrottle logo now belongs to the iOS launch screen instead of the in-app first screen

Use this block for GitHub releases, TestFlight notes, and App Store Connect:

> **TimeThrottle 2.0**
>
> - Opens directly to a full-screen map with no bottom tab bar
> - Moves route setup into an Apple Maps-style bottom panel
> - Adds route-free Log Trip for destination-free drive tracking
> - Opens Trip History and Scanner from Menu sheets
> - Keeps Scanner independent and preserves Apple Maps ETA baseline mode

## Core Product

### Live Drive

Live Drive is the full product.

It supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default start
- Apple Maps-style address autocomplete
- route options and route preview
- map-first route setup in a bottom panel
- live GPS tracking
- pause, resume, and end trip controls
- a map-first active driving HUD
- in-app guidance based on Apple Maps route steps
- route weather checkpoints expected around arrival time
- OpenStreetMap speed limit estimates where available
- optional nearby low aircraft display
- optional passive enforcement alerts when a configured source is available
- optional spoken camera-report and nearby-low-aircraft cues that respect global voice mute
- Trip History for completed drives
- shareable finished-trip summaries
- optional navigation handoff to Apple Maps, Google Maps, or Waze
- Menu access to Trip History, Scanner, route intelligence, display, and audio settings

### Scanner

Scanner is separate from Live Drive and opens from Menu.

It supports:
- public scanner listening
- Nearby scanner systems when location access is available
- Browse and search by system name, short name, city, county, or state
- optional Live Feed playback when a permitted direct stream URL is configured
- latest public scanner calls for a selected system
- separate Live Feed and Latest Calls replay playback modes
- simple play / pause / next-call playback for latest calls
- background audio while scanner playback is active

Scanner uses an OpenMHz-style API client with a configurable base URL for Latest Calls and a bundled approved-direct-stream config for optional Live Feed playback. It can point to a hosted OpenMHz endpoint, a self-hosted OpenMHz endpoint, or a compatible backend later. Scanner is listening only: TimeThrottle does not scrape Broadcastify, does not record scanner audio, does not upload scanner feeds, and does not use scanner audio for Live Drive, route warnings, incident prediction, or driving recommendations.

### Map-First Driving HUD

The map-first shell is the primary driving view built from real TimeThrottle trip state.

It shows:
- a full-width live map with route polyline, current location, route weather checkpoint markers, aircraft markers, enforcement alert markers when available, and recenter control
- next maneuver and distance based on Apple Maps route steps
- a compact floating weather chip when route forecast data is available
- a compact nearest-aircraft bar when the aircraft layer is enabled and data exists
- voice guidance mute / unmute control
- Current Speed
- Speed Limit estimate or Unavailable state
- Apple Maps ETA as the Apple Maps baseline
- Arrive as projected arrival in the destination's local time when available
- remaining route distance
- distance driven
- Pause / Resume and End Trip controls without opening Menu
- Menu access for route intelligence details

The Menu sheet holds:
- route weather status and forecast checkpoints
- optional Nearby Low Aircraft status, details, and audio cue control
- optional passive Enforcement Alerts, red-light camera filtering, enforcement-report filtering, and camera audio cue control when configured
- local voice guidance settings
- speed-limit source and confidence details
- Time Above Speed Limit
- Time Below Speed Limit
- average speed
- top speed
- Standard / Satellite map mode

Aircraft, enforcement, weather, and speed-limit data are informational and coverage varies by source, region, route, and app configuration.

The Map follows the user during a drive, stops following if the user pans away, and provides a clear recenter control. Route guidance is based on Apple Maps route data; it is not Apple-native navigation or lane guidance.

## Trip Results

Finished trips focus on the pace story:
- **Time Above Speed Limit** = measured time spent above available OpenStreetMap speed-limit estimates
- **Time Below Speed Limit** = measured time spent below available OpenStreetMap speed-limit estimates
- **Overall vs Apple ETA baseline** = the finished trip result against the Apple Maps ETA baseline

Speed-limit analysis only includes route segments where an OpenStreetMap speed-limit estimate was available.

## Navigation Handoff

TimeThrottle keeps Apple Maps as the route-planning and ETA-baseline layer.

In-app guidance is based on Apple Maps route steps. TimeThrottle does not claim lane guidance, certified speed-limit accuracy, live traffic ownership, aviation safety alerts, or Apple-native navigation behavior.

During Live Drive, users can choose:
- **Apple Maps**
- **Google Maps**
- **Waze**

TimeThrottle starts tracking first, then opens the selected navigation app if background-location requirements are met.

## Privacy at a Glance

- No user account is required
- Apple Maps is used for route lookup, autocomplete resolution, route options, and ETA baseline planning
- WeatherKit may be used for route weather forecasts near sampled route checkpoints
- OpenStreetMap may be queried and locally cached for speed-limit estimates where available
- OpenSky ADS-B may be queried on a conservative refresh interval when the optional passive Nearby Low Aircraft layer is enabled; stale or unavailable data is handled quietly and is not a safety system
- Passive Enforcement Alerts default on for fresh installs and may use OpenStreetMap Overpass or another configured open-data lookup where available; coverage varies by region, users can turn the layer off, and alerts are not guaranteed legal or enforcement guidance
- Scanner may use location to find nearby public scanner systems when Scanner Nearby is used
- Scanner audio comes from configured third-party or public scanner feed providers; TimeThrottle does not record scanner audio
- Live Feed appears only when a permitted direct stream URL is configured
- Scanner playback can continue in the background when the user starts scanner audio
- Live Drive uses iPhone location services when the user enables them
- Completed Live Drive trips are stored locally on-device
- The preferred navigation app choice is stored locally on-device
- The selected local iOS guidance voice, mute state, and speech speed are stored locally on-device
- Sharing only happens when the user explicitly uses the iOS share sheet

For the full policy, see [privacy-policy.md](privacy-policy.md).

## Tech Overview

- **Platform:** iPhone / iOS only
- **Deployment target:** iOS 17+
- **Bundle ID:** `com.timethrottle.app`
- **Current release:** v2.0
- **Current build:** 25
- **Primary app target:** `TimeThrottle.xcodeproj`
- **Primary shared UI:** `Sources/SharedUI/RouteComparisonView.swift`

### Core Components

- `LiveDriveTracker.swift` — Live Drive tracking, permission state, speed, and distance updates
- `TurnByTurnGuidanceEngine.swift` — Apple Maps route-step guidance, speech prompts, off-route detection, and reroute request foundation
- `VoiceGuidanceSettings.swift` — local iOS system voice settings, Daniel fresh-install default resolution, and English fallback selection
- `WeatherRouteProvider.swift` — distance-scaled route checkpoint sampling and WeatherKit forecast pipeline
- `SpeedLimitProvider.swift` / `OSMSpeedLimitService.swift` / `OSMSpeedLimitProvider.swift` — speed-limit estimate protocol, current-road OpenStreetMap lookup, and local cache wrapper
- `AircraftProvider.swift` / `OpenSkyAircraftProvider.swift` — optional passive Nearby Low Aircraft models, approximate position projection, and OpenSky implementation
- `EnforcementAlertProvider.swift` — optional camera and enforcement report models, OpenStreetMap Overpass provider/service path, filtering toggles, and capped route-aware visibility policy
- `ScannerModels.swift` — public scanner system, call, talkgroup, nearby sorting, and geocode cache models
- `OpenMHzScannerService.swift` — configurable OpenMHz-style scanner API client for systems, latest calls, and talkgroups
- `ScannerLiveStreamCatalog.swift` — approved direct live-stream config models, validation, and selected-system resolver
- `TripHistoryStore.swift` — local persistence for completed Live Drive trips
- `TripAnalysisEngine.swift` — live pace and trip summary generation
- `PaceAnalysisMath.swift` — shared speed-limit comparison helper
- `RouteModels.swift` — shared route, lookup, autocomplete, and navigation-provider models
- `LiveDriveHUDView.swift` — legacy compact driving-view component retained internally while Map is the primary driving HUD
- `LiveDriveHUDMapView_iOS.swift` — Map follow, route polyline, route weather checkpoint markers, user location, aircraft markers, enforcement alert markers, and recenter behavior
- `NavigationHandoffService.swift` — Apple Maps / Google Maps / Waze handoff behavior
- `ScannerViewModel.swift` — Scanner systems, Nearby/Browse, selected system, Live Feed availability, latest calls, and player state
- `ScannerTabView.swift` — Scanner sheet UI, system lists, selected-system Live Feed card, latest calls, and player controls

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
