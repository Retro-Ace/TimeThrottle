# TimeThrottle

**TimeThrottle** is an iPhone app that helps drivers understand whether driving faster actually saves meaningful time compared to the added downsides.

Instead of relying on guesswork, TimeThrottle compares a user’s pace against a selected baseline and shows the tradeoff between time saved, time under target pace, fuel penalty, ticket risk, and overall trip balance.

> **How much time did speed really buy you?**

---

## Features

### Live Drive
Live Drive lets users compare a real drive against a selected Apple Maps route baseline.

Users can:
- Enter a start address and destination
- Calculate Apple Maps routes
- Choose a route option
- Preview the selected route
- Start a live tracked drive

While driving, the app can show:
- Current speed
- Distance driven
- Time under target pace
- Trip balance
- Live route map
- Live comparison bar

### Route Mode
Route mode compares a planned trip against an Apple Maps route and ETA baseline.

It includes:
- Start and destination entry
- Apple Maps route lookup
- Route options
- Route preview
- Selected route distance
- Apple ETA baseline
- Pace comparison
- Comparison bars
- “Was it worth it?” summary

### Manual Mode
Manual mode is the simplest calculator mode and works without route lookup.

Users can enter:
- Posted speed limit
- Miles driven
- Average speed or trip duration
- Vehicle rated MPG
- Observed MPG at pace
- Fuel price

The app then calculates:
- Time saved
- Time under target pace
- Fuel penalty
- Ticket risk
- Trip balance

---

## Apple Maps + Live GPS

TimeThrottle uses Apple Maps route information to create route-based baselines and uses iPhone location services for Live Drive tracking.

Live Drive preserves selected route context into the active trip so the user can continue seeing route context while driving.

---

## Product Direction

TimeThrottle is built around three modes:

- **Live Drive** — track a real trip in motion
- **Route** — compare against Apple Maps route pace
- **Manual** — enter your own baseline values

The app uses truthful pace-based language and avoids implying real traffic detection when it is only measuring slower-than-target travel.

---

## Tech Overview

- **Platform:** iOS / iPhone only
- **Deployment target:** iOS 17+
- **Bundle ID:** `com.timethrottle.app`
- **Primary app entry:** `Sources/iOS/TimeThrottleApp_iOS.swift`
- **Main shared UI:** `Sources/SharedUI/RouteComparisonView.swift`

### Core Components
- `LiveDriveTracker.swift` — live trip tracking, permission state, distance and speed updates
- `TripAnalysisEngine.swift` — live trip analysis and summary generation
- `SpeedCostCalculator.swift` — speed/fuel/cost comparison math
- `TimeThrottleCalculator.swift` — manual and segment-style trip calculations
- `RouteModels.swift` — shared route and mode data models

---

## Project Structure

```text
TimeThrottle
│
├── TimeThrottle.xcodeproj
├── TimeThrottle.xcworkspace
├── Package.swift
├── README.md
│
├── Assets.xcassets
│   ├── AppIcon
│   └── other visual assets
│
├── Sources
│   ├── iOS
│   │   ├── TimeThrottleApp_iOS.swift
│   │   ├── IOSRouteComparisonScreen.swift
│   │   └── RoutePreviewMapView_iOS.swift
│   │
│   ├── Core
│   │   ├── TimeThrottleCalculator.swift
│   │   ├── SpeedCostCalculator.swift
│   │   ├── LiveDriveTracker.swift
│   │   ├── TripAnalysisEngine.swift
│   │   └── other calculation / model files
│   │
│   └── SharedUI
│       ├── RouteComparisonView.swift
│       ├── RouteModels.swift
│       ├── SharedComponents.swift
│       ├── PlatformLayout.swift
│       └── related shared UI/helpers
│
├── Tests
│   ├── CoreTests
│   │   ├── SpeedCostCalculatorTests.swift
│   │   ├── TripAnalysisEngineTests.swift
│   │   ├── TimeThrottleCoreTests.swift
│   │   └── other tests
│
├── dist
│   └── iOSSimulator
│       └── TimeThrottle.app
│
└── scripts / build outputs
    └── dist-ios
```

---

## Development Workflow

TimeThrottle was developed using a 3-agent workflow:

### Dan — Implementation / Architecture / Logic
- Cleaned the repo to iOS-only
- Built the Live Drive tracker and trip analysis engine
- Integrated route context into Live Drive
- Fixed permission flow and naming consistency
- Preserved Route and Manual behavior while adding new features

### Steve — UI / UX / Product Flow
- Reworked the app into a clear mode-based structure
- Improved Live Drive setup, driving, and trip-complete states
- Added the live route map and live comparison bar
- Simplified active driving UI for clarity and safety

### Joe — QA / Validation / Release Readiness
- Audited platform cleanup and wiring
- Flagged misleading semantics and permission issues
- Verified wording consistency and release readiness
- Final QA result: **ready for TestFlight**

---

## Current Release State

- iOS only
- iPhone only
- TestFlight-ready
- Simulator build and launch verified
- Real-world on-device validation still recommended before broad release

Suggested next version:
- **Version:** 1.1
- **Build:** 2

---

## Privacy

TimeThrottle does not require user accounts.

The app may request location access for Live Drive tracking. Route and trip calculations are intended to work without collecting personal accounts or selling user data.

For the full policy, see [`privacy-policy.md`](privacy-policy.md).

---

## Roadmap Ideas

Potential future additions:
- Trip history
- Shareable trip summary cards
- More real-world drive testing and battery optimization
- Additional visual summaries for Live Drive results

---

## Contact

For questions about TimeThrottle, update this section with your preferred support contact before public release.
