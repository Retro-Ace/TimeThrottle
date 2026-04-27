# TimeThrottle — Master Project Document (v2.0)

> Start here after `README.md` when you need a fuller product and project reference.
>
> - Read `README.md` first for the quickest overview.
> - Use this file for a broader current-state explanation.
> - Read `TimeThrottle_Developer_Handoff.md` instead if you only need the short handoff version.

## Overview

**TimeThrottle** is an iPhone Live Drive pace-analysis app built around one question:

> **How much time did speed really buy you?**

The app uses **Apple Maps** for route lookup, route options, autocomplete, and the ETA baseline. During a real drive, TimeThrottle tracks the trip and shows:
- Time Above Speed Limit
- Time Below Speed Limit
- projected arrival versus the Apple Maps ETA baseline

TimeThrottle is **not** an Apple Maps replacement or Apple-native navigation engine. It can optionally hand off navigation to **Apple Maps, Google Maps, or Waze** while continuing to track the trip.

## Current Product Structure

As of **v2.0**, the active iPhone product is centered on **Live Drive** with the Map tab as the primary driving HUD, plus a separate Scanner tab for informational public scanner listening.

### Live Drive

Live Drive supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default route start
- Apple Maps-style autocomplete
- route selection and preview
- live GPS tracking
- pause / resume / end trip
- Map tab active driving HUD
- in-app guidance based on Apple Maps route steps
- route weather checkpoints shown as forecasts near the route and expected around arrival time
- OpenStreetMap speed-limit estimates where available, with local caching to avoid repeated segment lookups
- optional passive Nearby Low Aircraft display using OpenSky ADS-B data
- optional passive Enforcement Alerts from the configured OpenStreetMap Overpass camera/enforcement source when tagged data is available
- Standard / Satellite map mode with local persistence
- direct Map tab Pause / Resume and End Trip controls
- always-visible floating Map recenter control
- compact floating weather chip when route forecast data is available
- compact nearest-aircraft Map bar when the aircraft layer is enabled and data exists
- a Map tab Options panel for weather, aircraft, voice, speed-limit, pace, Enforcement Alerts, Map Mode, average speed, and top speed details
- Trip History storage
- shareable finished-trip summaries
- optional external navigation handoff
- bottom navigation for Drive, Map, Trips, and Scanner

### Scanner

Scanner is separate from Live Drive and does not feed driving calculations, route intelligence, route warnings, trip results, or navigation handoff.

Scanner supports:
- public scanner listening
- Nearby scanner systems when location is available
- Browse and search by system name, short name, city, county, or state
- latest public scanner calls for a selected system
- selected-call or latest-playable call play / pause / next-call playback
- background audio while scanner playback is active
- graceful unavailable states when provider data or audio is unavailable

Scanner uses a configurable OpenMHz-style API client for systems, latest calls, and talkgroups. TimeThrottle does not record scanner audio, does not support user-uploaded scanner feeds, and does not claim provider coverage or freshness guarantees.

## Live Drive Results

Finished trips focus on pace and time only.

Result language:
- **Time Above Speed Limit** = measured time spent above available OpenStreetMap speed-limit estimates
- **Time Below Speed Limit** = measured time spent below available OpenStreetMap speed-limit estimates
- **Overall vs Apple ETA baseline** = completed trip result against the Apple Maps ETA baseline
- **Top speed** = highest valid GPS speed sample saved for the trip when available

Speed-limit analysis only includes route segments where an OpenStreetMap speed-limit estimate was available.

## Map Tab Driving HUD

The Map tab is the primary active driving surface.

### Map goals
- map-first driving context
- direct access to Pause / Resume and End Trip
- supportive map context without pretending to be full navigation
- route-step guidance, mute control, off-route status, and reroute status
- Speed Limit estimate / Unavailable state
- Apple Maps ETA, projected arrival, route distance, and miles driven
- clear Apple Maps ETA / Arrive / Time Above Speed Limit / Time Below Speed Limit hierarchy
- Options sheet access for route forecast, aircraft, enforcement alerts, voice, speed-limit details, pace, map mode, average speed, and top speed

### Map behavior
- follows the user by default
- stops following if the user pans away
- shows a clear recenter control
- resumes follow mode on recenter
- uses a stable driving-oriented zoom instead of constantly re-fitting the route
- keeps the route polyline, current location, aircraft markers, and enforcement alert markers visible when data is available

## App Navigation

v2.0 uses a bottom app navigation structure:
- **Drive** = Live Drive setup, Current Location start, destination input, route options, compact navigation app choice, and Start Drive
- **Map** = primary active driving HUD with route polyline, user location, next maneuver, speed, Speed Limit estimate where available, Apple Maps ETA, projected arrival, route distance, miles driven, Pause / Resume, End Trip, recenter, and an Options panel for route-intelligence details
- **Trips** = Trip History list and trip detail screens
- **Scanner** = public scanner listening with Nearby / Browse system discovery, latest calls, and playback

Switching between these tabs preserves the active trip state.

The Map Options panel keeps weather checkpoints, Nearby Low Aircraft status/toggle, optional Enforcement Alerts, Standard / Satellite map mode, local voice guidance controls, speed-limit source details, and pace details out of the always-visible map view. Aircraft, enforcement, weather, and speed-limit data are informational and coverage varies by source, region, route, and app configuration.

## Core Product Truth

TimeThrottle currently does:
- real Live Drive tracking
- Apple ETA-baseline comparison
- in-app guidance based on Apple Maps route steps
- route weather checkpoints
- speed-limit estimates where OpenStreetMap data is available, with confidence and local cache support
- optional passive nearby low aircraft from OpenSky ADS-B data, refreshed conservatively and removed when stale
- optional passive camera/enforcement alerts from configured providers when available; coverage varies by region and alerts are not guaranteed
- separate public scanner listening with OpenMHz-style systems, latest calls, talkgroups, and playback
- Standard / Satellite map mode
- local iOS system voice selection with persisted voice, mute, and speech speed settings
- trip result review
- Trip History storage
- optional external navigation handoff

TimeThrottle does **not** currently claim:
- Apple-native turn-by-turn navigation
- lane guidance
- certified road speed-limit accuracy
- live traffic ownership
- aviation safety or collision-avoidance alerts
- certain enforcement detection
- scanner audio recording
- scanner-based route warnings or driving recommendations

## Development History

- early iPhone app stage: baseline route planning and pace analysis
- Apple Maps stage: route lookup, route options, route preview, ETA baseline
- Live Drive expansion: GPS tracking, route context preservation, finished-trip persistence
- handoff stage: Apple Maps / Google Maps / Waze external navigation handoff
- compact driving-view stage: focused in-app Live Drive view
- v1.4.2: Live Drive-only simplification, removed old non-Live features, and improved map follow behavior
- v1.4.3: speed-entry wording cleanup, consolidated trip summaries, compact driving-view polish, and destination-time-zone arrival formatting
- v1.5.0: user-facing route-step guidance, route weather checkpoints, speed-limit estimate display, optional nearby aircraft layer, and route-intelligence privacy/docs updates
- v1.5.1: refined aircraft into passive Nearby Low Aircraft, added distance/altitude/staleness filtering, strengthened OpenStreetMap current-road speed-limit lookup, and added local speed-limit cache support
- v1.5.2: removed user-entered speed input, moved pace analysis to available OpenStreetMap speed-limit estimates, and clarified route forecast unavailable/loading wording
- v1.5.3: added bottom navigation, a dedicated map-first route view, and improved local iOS system voice guidance
- v1.5.4: polished map-fill behavior, added the Map Options panel, refreshed Nearby Low Aircraft data on a live interval with stale cleanup, and persisted selected local iOS voice settings
- v1.5.5: added optional Enforcement Alerts foundation, Standard / Satellite map mode, Top speed tracking, simplified Drive setup, and compact navigation app selection
- v1.5.6: simplified navigation to Drive / Map / Trips, made Map the primary driving HUD with direct Pause / Resume and End Trip, and cleaned Trips around speed-limit-based results, distance, average speed, and top speed
- v1.5.7: added a floating Map recenter control and compact floating weather chip for quick-glance route conditions
- v1.5.8: defaulted aircraft on, made recenter icon-only, fixed weather chip icon rendering, and added a nearest-aircraft Map bar
- v1.5.9: polished the Map-first driving hierarchy, consolidated route intelligence into Options, and cleaned Trips wording around ETA, speed-limit analysis, top speed, and speed-limit coverage
- v2.0: added a separate Scanner tab with Nearby / Browse public scanner systems, latest calls, OpenMHz-style service models, playback, background audio, and privacy updates
- v2.0 build 19: added real-device WeatherKit entitlement wiring and diagnostics, fixed Scanner latest-call/playback loading states, defaulted passive Enforcement Alerts on for fresh installs, and added fresh ADS-B aircraft map markers
- v2.0 build 20: fixed real-device Scanner playback startup, cleaned WeatherKit signed-build unavailable UI, defaulted fresh installs to Daniel when available, added the OpenStreetMap Overpass Enforcement Alerts source path, and raised passive aircraft/enforcement marker visibility priority
- v2.0 build 21: added Scanner audio-session fallback diagnostics, raised aircraft/enforcement map annotation reliability, and broadened conservative OpenStreetMap traffic-camera tag coverage
- v2.0 build 22: capped Enforcement Alerts for performance, prioritized route-relevant and ahead-of-travel alerts within 3.5 miles, added a 25-alert nearby fallback within 3.0 miles when no route is active, and clarified capped-count wording
- v2.0 build 23: keeps Map usable without an active route, clears old route overlays after End Trip, raises visible Enforcement Alerts to 50, removes the Enforcement list from Options, simplifies navigation handoff choices, and scales Route Forecast checkpoints by distance

## Repo / App Structure

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

## Current Release State

- **Version:** 2.0
- **Build:** 23

## Plain-English Summary

**TimeThrottle is now a Live Drive-first iPhone pace-analysis app with Drive / Map / Trips / Scanner navigation. Map is the primary driving HUD, while Options holds route intelligence details. Scanner is separate and provides informational public scanner listening through Nearby / Browse systems, latest calls, and selected/latest-call playback. The app uses Apple Maps as the route and ETA-baseline layer, tracks real trips, adds truthful route-step guidance, persistent local system voice prompts with Daniel as the fresh-install default when available, route weather, cached OpenStreetMap speed-limit estimates, optional passive Nearby Low Aircraft with stale-data handling, optional OpenStreetMap Overpass-backed Enforcement Alerts with varied coverage, Standard / Satellite map mode, local Trip History, external navigation handoff, and finished-trip results centered on Time Above Speed Limit, Time Below Speed Limit, Top speed, and Apple Maps ETA baseline.**
