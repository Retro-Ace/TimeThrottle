# Changelog

All notable release-facing changes to **TimeThrottle** should be documented in this file.

## v1.3.2 - April 6, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.3.2**
>  
> - Added a cleaner compact Live Drive HUD for in-motion use
> - Improved one-screen HUD fit so trip status, Apple ETA, projected arrival, and controls are easier to reach
> - Clarified HUD metric wording around Apple ETA and target-speed time
> - Better balanced the lower HUD map area without claiming built-in navigation
> - Kept the app focused on two modes: Live Drive and Compare

### Release Notes

- Added a compact in-app Live Drive HUD that opens when a drive starts
- Kept current speed as the HUD hero metric while tightening the route header, metric cards, and controls
- Added real trip-average-speed and projected-arrival context using existing Live Drive data
- Kept Apple ETA as the baseline reference in the HUD and avoided fake traffic, road speed-limit, or turn-by-turn claims
- Improved HUD control reachability so Pause / Resume and End Trip stay easier to reach
- Rebalanced the lower HUD map area so it fills the remaining screen space more naturally
- Left Compare and the Apple Maps planning baseline unchanged

### Release Positioning

TimeThrottle 1.3.2 is a Live Drive usability update focused on the compact in-app HUD. The app remains centered on Live Drive and Compare, Apple Maps still provides route lookup and ETA baseline planning, and TimeThrottle continues to analyze pace tradeoffs without claiming built-in turn-by-turn navigation.

## v1.3.1 - March 24, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.3.1**
>  
> - Clarified finished-trip result labels so Above-target gain, Below-target loss, and Overall vs Apple ETA are clearly separated
> - Updated Trip History, trip detail, and shared trip summaries to use the same Apple ETA baseline framing
> - Tightened in-app and release-facing wording around finished-trip metrics for consistency
> - Simplified the active iPhone app structure so it now centers on Live Drive and Compare

### Release Notes

- No trip-analysis math changed in this update
- Clarified that Above-target gain measures only time gained from above-target pace segments
- Clarified that Below-target loss measures time lost while driving below target pace
- Clarified that Overall vs Apple ETA is the completed-trip result against the Apple Maps ETA baseline
- Updated share text, Trip History, trip detail, and release-facing copy to match the clarified result story
- Removed Manual from the active iPhone flow
- Kept Compare focused on the Apple Maps ETA-baseline planning and simulation path
- Left Live Drive behavior unchanged in this simplification pass

### Release Positioning

TimeThrottle 1.3.1 is a wording and consistency update focused on finished-trip clarity and the simplified two-mode iPhone flow. Apple Maps still provides route lookup and ETA baseline planning, Compare remains the simulation mode built around that baseline, and Live Drive continues to track real trips without claiming built-in turn-by-turn navigation.

## v1.3 - March 22, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

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
> - Added a small reminder to obey traffic laws and road conditions

### Release Notes

- Kept Apple Maps as the route lookup and ETA baseline layer
- Added Pause / Resume / End Trip control flow for active Live Drive sessions
- Kept finished trips visible after completion instead of wiping the result immediately
- Added optional Observed MPG refinement to recalculate post-trip fuel penalty
- Added local Trip History for completed Live Drive trips
- Added a shareable finished-trip summary for the iOS share sheet
- Added Waze alongside Apple Maps, Google Maps, and Ask Every Time for navigation handoff
- Improved the Live Drive provider selector and elapsed-trip status treatment
- Added a destination clear control and tighter route-state reset behavior
- Added a small safety note: “Always obey traffic laws and road conditions.”

### Release Positioning

TimeThrottle 1.3 is an iPhone pace-analysis release focused on Live Drive completion and post-trip usefulness. Apple Maps still provides route lookup and ETA baseline planning, while Live Drive can optionally hand off navigation to Apple Maps, Google Maps, or Waze and continue tracking pace tradeoffs without claiming built-in turn-by-turn navigation.

## v1.2 - March 19, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.2**
>  
> - Added external navigation handoff for Live Drive
> - Choose Apple Maps, Google Maps, or Ask Every Time
> - Current Location is now the default route start
> - Added Apple Maps-style address autocomplete
> - Cleaned up the Live Drive setup flow
> - Tightened truthful pace-based wording across the app
> - Refined Live Drive, Route, and Manual into a more consistent iPhone experience

### Release Notes

- Kept Apple Maps as the route lookup and ETA baseline layer
- Added provider-agnostic Live Drive handoff to Apple Maps or Google Maps
- Added clean fallback behavior when Google Maps is not installed
- Preserved TimeThrottle as the trip-analysis engine during Live Drive
- Added Current Location as the default route start for route setup
- Added Apple Maps-style autocomplete for route address entry
- Improved Live Drive setup hierarchy and visual consistency
- Brought Manual mode closer to the same design system as Route and Live Drive
- Kept pace-based wording truthful across Live Drive, Route, and Manual

### Release Positioning

TimeThrottle 1.2 is an iPhone pace-analysis release. It does not add built-in turn-by-turn navigation. Apple Maps still provides route lookup and ETA baseline planning, while Live Drive can optionally hand off navigation to Apple Maps or Google Maps and continue tracking pace tradeoffs.
