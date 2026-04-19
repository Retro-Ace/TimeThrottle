# TimeThrottle — Master Project Document (v1.4.3)

## Overview

**TimeThrottle** is an iPhone Live Drive pace-analysis app built around one question:

> **How much time did speed really buy you?**

The app uses **Apple Maps** for route lookup, route options, autocomplete, and the ETA baseline. During a real drive, TimeThrottle tracks the trip and shows:
- Time Above Set Speed
- Time Below Set Speed
- projected arrival versus the Apple Maps ETA baseline

TimeThrottle is **not** a built-in turn-by-turn navigation app. It can optionally hand off navigation to **Apple Maps, Google Maps, or Waze** while continuing to track the trip.

## Current Product Structure

As of **v1.4.3**, the active iPhone product is intentionally centered on **Live Drive only**.

### Live Drive

Live Drive supports:
- Apple Maps route lookup and ETA baseline
- Current Location as the default route start
- Apple Maps-style autocomplete
- route selection and preview
- desired-speed entry before the drive starts
- live GPS tracking
- pause / resume / end trip
- compact in-app Live Drive HUD
- Trip History storage
- shareable finished-trip summaries
- optional external navigation handoff

## Live Drive Results

Finished trips focus on pace and time only.

Result language:
- **Time Above Set Speed** = total time spent above the chosen desired speed
- **Time Below Set Speed** = total time spent below the chosen desired speed
- **Overall vs Apple ETA baseline** = completed trip result against the Apple Maps ETA baseline

## Live Drive HUD

The compact Live Drive HUD is one of the most important current product features.

### HUD goals
- more glanceable than the regular active Live Drive screen
- current speed as the hero metric
- compact route/header footprint
- faster access to Pause / Resume and End Trip
- supportive map context without pretending to be full navigation
- clear Apple Maps ETA / Arrive / Time Above Set Speed / Time Below Set Speed hierarchy

### HUD map behavior
- follows the user by default
- stops following if the user pans away
- shows a clear recenter control
- resumes follow mode on recenter
- uses a stable driving-oriented zoom instead of constantly re-fitting the route

## Core Product Truth

TimeThrottle currently does:
- real Live Drive tracking
- Apple ETA-baseline comparison
- trip result review
- Trip History storage
- optional external navigation handoff

TimeThrottle does **not** currently claim:
- built-in turn-by-turn navigation
- lane guidance
- road speed-limit ownership
- live traffic ownership

## Development History

- early iPhone app stage: baseline route planning and pace analysis
- Apple Maps stage: route lookup, route options, route preview, ETA baseline
- Live Drive expansion: GPS tracking, route context preservation, finished-trip persistence
- handoff stage: Apple Maps / Google Maps / Waze external navigation handoff
- HUD stage: compact in-app Live Drive HUD
- v1.4.2: Live Drive-only simplification, removed old non-Live features, improved HUD map follow behavior
- v1.4.3: desired-speed wording cleanup, consolidated trip summaries, HUD polish, and destination-time-zone arrival formatting

## Repo / App Structure

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

## Current Release State

- **Version:** 1.4.3
- **Build:** 7

## Plain-English Summary

**TimeThrottle is now a Live Drive-first iPhone pace-analysis app. It uses Apple Maps as the route and ETA-baseline layer, tracks real trips, saves Trip History locally, supports optional external navigation handoff, and focuses finished-trip results on Time Above Set Speed, Time Below Set Speed, and projected arrival versus Apple Maps ETA baseline.**
