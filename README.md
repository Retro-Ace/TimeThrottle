<p align="center">
  <img src="Assets/timethrottle-banner.png" width="900">
</p>

<h1 align="center">TimeThrottle</h1>

<p align="center">
How much time did speed really buy you?
</p>

**TimeThrottle** is an iPhone pace-analysis app that helps drivers understand what faster driving actually bought them.

Apple Maps provides route lookup, autocomplete, route options, and the ETA baseline. TimeThrottle then tracks or compares pace tradeoffs such as above-target gain, below-target loss, fuel penalty, ticket-risk estimate, and overall result versus Apple ETA where that baseline exists.

TimeThrottle does **not** provide built-in turn-by-turn navigation. In **Live Drive**, it can hand off navigation to Apple Maps, Google Maps, or Waze while TimeThrottle continues tracking the trip and comparing pace tradeoffs.

> **How much time did speed really buy you?**

## What's New in v1.3.1

Use this block for GitHub, TestFlight, and App Store Connect release copy:

> **TimeThrottle 1.3.1**
>  
> - Clarified finished-trip result labels so Above-target gain, Below-target loss, and Overall vs Apple ETA are clearly separated
> - Updated Trip History, trip detail, and shared trip summaries to use the same Apple ETA baseline framing
> - Tightened in-app and release-facing wording around finished-trip metrics for consistency

## What's New in v1.3

Use this block for GitHub, TestFlight, and App Store Connect release copy:

> **TimeThrottle 1.3**
>  
> - Added Pause, Resume, and End Trip controls for Live Drive
> - Finished trips now stay visible after completion
> - Added optional Observed MPG fuel refinement after a drive
> - Added Trip History for completed Live Drive trips
> - Added a shareable finished-trip summary
> - Added Waze as a navigation handoff option
> - Improved the navigation provider selector and trip-status timing
> - Added a destination clear control during route setup
> - Added a small safety reminder to obey traffic laws and road conditions

## Core Modes

### Live Drive

Live Drive is the real-time trip analysis mode.

It can:
- Capture an Apple Maps route and ETA baseline
- Use Current Location as the default route start
- Offer Apple Maps-style address autocomplete for route setup
- Track speed, distance, and trip progress with iPhone location services
- Pause, resume, and end the active trip without losing the finished result
- Compare live projected pace against the Apple ETA baseline
- Show above-target gain, below-target loss, fuel penalty, and overall result vs Apple ETA on completed trips
- Keep completed trips visible for review, sharing, and optional Observed MPG refinement
- Save completed Live Drive trips into local Trip History
- Hand off navigation to Apple Maps, Google Maps, or Waze without claiming built-in navigation

### Route

Route mode compares a planned or completed trip against an Apple Maps route and ETA baseline.

It includes:
- Apple Maps route lookup
- Route options
- Route preview
- Apple ETA baseline
- Pace comparison
- Fuel and ticket-risk estimates
- Comparison bars and trip summary output

### Manual

Manual mode compares two paces across a hand-entered distance.

It includes:
- Distance entry
- Speed A vs Speed B comparison
- Average-speed or trip-duration comparison input
- Fuel assumptions
- Pace, fuel, and ticket-risk tradeoff output

## Navigation Handoff in v1.3.1

TimeThrottle 1.3.1 still keeps Apple Maps as the planning layer and Apple ETA baseline source.

During Live Drive, users can choose:
- **Apple Maps**
- **Google Maps**
- **Waze**
- **Ask Every Time**

When a Live Drive starts, TimeThrottle starts trip tracking first, then opens the selected navigation app if background continuity requirements are met. If Google Maps or Waze is not installed, the app falls back cleanly instead of leaving the user stuck.

## Product Positioning

TimeThrottle is a **pace-analysis app**, not a navigation replacement.

The app is designed to answer questions like:
- Did driving faster meaningfully change the trip?
- How much above-target gain did the trip create?
- How much below-target loss built up during the trip?
- How did the finished trip land versus the Apple ETA baseline?
- What was the fuel penalty?
- Was the overall tradeoff worth it?

## Safety Note

TimeThrottle includes a small reminder during Live Drive and trip review screens:

> **Always obey traffic laws and road conditions.**

## Privacy at a Glance

- No user account is required
- Apple Maps is used for route lookup, autocomplete resolution, route options, and ETA baseline planning
- Live Drive uses iPhone location services when the user enables them
- External navigation handoff is optional
- Completed Live Drive trips are stored locally on-device
- The preferred navigation app choice is stored locally on-device
- Sharing only happens when the user explicitly opens the iOS share sheet

For the full policy, see [privacy-policy.md](/Users/anthonylarosa/SPEED%20APP/privacy-policy.md).

## Tech Overview

- **Platform:** iPhone / iOS only
- **Deployment target:** iOS 17+
- **Bundle ID:** `com.timethrottle.app`
- **Current release:** v1.3.1
- **Current build:** 4
- **Primary app target:** `TimeThrottle.xcodeproj`
- **Primary shared UI:** `Sources/SharedUI/RouteComparisonView.swift`

### Core Components

- `LiveDriveTracker.swift` — Live Drive tracking, permission state, speed, and distance updates
- `TripHistoryStore.swift` — local persistence for completed Live Drive trips
- `TripAnalysisEngine.swift` — live pace/trip summary generation
- `SpeedCostCalculator.swift` — route/manual speed-cost math
- `TimeThrottleCalculator.swift` — manual and segment-based comparison math
- `RouteModels.swift` — shared route, lookup, autocomplete, and mode models
- `NavigationHandoffService.swift` — Apple Maps / Google Maps / Waze / Ask Every Time handoff behavior

## Repository Layout

```text
TimeThrottle
├── TimeThrottle.xcodeproj
├── TimeThrottle.xcworkspace
├── README.md
├── CHANGELOG.md
├── privacy-policy.md
├── Assets.xcassets
├── Resources
│   ├── iOS
│   ├── LaunchScreen.storyboard
│   └── TimeThrottleLogo
├── Sources
│   ├── Core
│   ├── SharedUI
│   └── iOS
├── Tests
│   └── CoreTests
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
