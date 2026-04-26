# TimeThrottle — Master Project Document (v1.5.5)

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

As of **v1.5.5**, the active iPhone product is centered on **Live Drive** with route intelligence layered on top of the Apple Maps route baseline.

### Live Drive

Live Drive supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default route start
- Apple Maps-style autocomplete
- route selection and preview
- live GPS tracking
- pause / resume / end trip
- compact in-app Live Drive HUD
- in-app guidance based on Apple Maps route steps
- route weather checkpoints shown as forecasts near the route and expected around arrival time
- OpenStreetMap speed-limit estimates where available, with local caching to avoid repeated segment lookups
- optional passive Nearby Low Aircraft display using OpenSky ADS-B data
- optional passive Enforcement Alerts when a configured camera/enforcement source is available
- Standard / Satellite map mode with local persistence
- a Map tab Options panel for weather, aircraft, voice, speed-limit, pace, Enforcement Alerts, and Map Mode details
- Trip History storage
- shareable finished-trip summaries
- optional external navigation handoff
- bottom navigation for Drive, HUD, Map, and Trips

## Live Drive Results

Finished trips focus on pace and time only.

Result language:
- **Time Above Speed Limit** = measured time spent above available OpenStreetMap speed-limit estimates
- **Time Below Speed Limit** = measured time spent below available OpenStreetMap speed-limit estimates
- **Overall vs Apple ETA baseline** = completed trip result against the Apple Maps ETA baseline
- **Top speed** = highest valid GPS speed sample saved for the trip when available

Speed-limit analysis only includes route segments where an OpenStreetMap speed-limit estimate was available.

## Live Drive HUD

The compact Live Drive HUD is one of the most important current product features.

### HUD goals
- more glanceable than the regular active Live Drive screen
- current speed as the hero metric
- compact route/header footprint
- faster access to Pause / Resume and End Trip
- supportive map context without pretending to be full navigation
- route-step guidance, mute control, off-route status, and reroute status
- Speed Limit estimate / Unavailable state
- route weather and optional Nearby Low Aircraft status
- clear Apple Maps ETA / Arrive / Time Above Speed Limit / Time Below Speed Limit hierarchy
- lightweight local system voice controls for mute, voice choice, test prompt, and speech speed

### HUD map behavior
- follows the user by default
- stops following if the user pans away
- shows a clear recenter control
- resumes follow mode on recenter
- uses a stable driving-oriented zoom instead of constantly re-fitting the route
- fills the available lower HUD and Map tab space more cleanly above the bottom tab bar

## App Navigation

v1.5.5 uses a bottom app navigation structure:
- **Drive** = Live Drive setup, Current Location start, destination input, route options, compact navigation app choice, and Start Drive
- **HUD** = focused active driving dashboard, or an empty state when no trip is active
- **Map** = map-first route view with route polyline, user location, next maneuver, speed, Speed Limit estimate where available, recenter support, and an Options panel for route-intelligence details
- **Trips** = Trip History list and trip detail screens

Switching between these tabs preserves the active trip state.

The Map Options panel keeps weather checkpoints, Nearby Low Aircraft status/toggle, optional Enforcement Alerts, Standard / Satellite map mode, local voice guidance controls, speed-limit source details, and pace details out of the always-visible map view.

## Core Product Truth

TimeThrottle currently does:
- real Live Drive tracking
- Apple ETA-baseline comparison
- in-app guidance based on Apple Maps route steps
- route weather checkpoints
- speed-limit estimates where OpenStreetMap data is available, with confidence and local cache support
- optional passive nearby low aircraft from OpenSky ADS-B data, refreshed conservatively and removed when stale
- optional passive camera/enforcement alerts from configured providers when available; coverage varies by region and alerts are not guaranteed
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
- guaranteed enforcement or police detection

## Development History

- early iPhone app stage: baseline route planning and pace analysis
- Apple Maps stage: route lookup, route options, route preview, ETA baseline
- Live Drive expansion: GPS tracking, route context preservation, finished-trip persistence
- handoff stage: Apple Maps / Google Maps / Waze external navigation handoff
- HUD stage: compact in-app Live Drive HUD
- v1.4.2: Live Drive-only simplification, removed old non-Live features, improved HUD map follow behavior
- v1.4.3: desired-speed wording cleanup, consolidated trip summaries, HUD polish, and destination-time-zone arrival formatting
- v1.5.0: user-facing route-step guidance, route weather checkpoints, speed-limit estimate display, optional nearby aircraft layer, and route-intelligence privacy/docs updates
- v1.5.1: refined aircraft into passive Nearby Low Aircraft, added distance/altitude/staleness filtering, strengthened OpenStreetMap current-road speed-limit lookup, and added local speed-limit cache support
- v1.5.2: removed user-entered Desired Speed, moved pace analysis to available OpenStreetMap speed-limit estimates, and clarified route forecast unavailable/loading wording
- v1.5.3: added bottom navigation, a dedicated map-first route view, and improved local iOS system voice guidance
- v1.5.4: polished HUD/Map bottom-fill behavior, added the Map Options panel, refreshed Nearby Low Aircraft data on a live interval with stale cleanup, and persisted selected local iOS voice settings
- v1.5.5: added optional Enforcement Alerts foundation, Standard / Satellite map mode, Top speed tracking, simplified Drive setup, and compact navigation app selection

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

- **Version:** 1.5.5
- **Build:** 13

## Plain-English Summary

**TimeThrottle is now a Live Drive-first iPhone pace-analysis app with route intelligence and clear bottom navigation. It uses Apple Maps as the route and ETA-baseline layer, tracks real trips, adds truthful route-step guidance, persistent local system voice prompts, route weather, cached OpenStreetMap speed-limit estimates, optional passive Nearby Low Aircraft with stale-data handling, optional provider-backed Enforcement Alerts with varied coverage, Standard / Satellite map mode, local Trip History, external navigation handoff, and finished-trip results centered on Time Above Speed Limit, Time Below Speed Limit, Top speed, and Apple Maps ETA baseline.**
