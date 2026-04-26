# Changelog

All notable release-facing changes to **TimeThrottle** should be documented in this file.

## v1.5.5 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.5**
>
> - Adds optional Enforcement Alerts for configured speed-camera, red-light-camera, and enforcement-report providers
> - Adds Standard / Satellite map mode selection with local persistence
> - Tracks Top speed during Live Drive and saves it to Trip Results and Trip History when valid GPS speed data is available
> - Simplifies Drive setup by removing Custom Start from the UI and replacing the large navigation-app list with a compact selector

### Release Notes

- Enforcement Alerts are optional, passive, and provider-backed; if no source is configured, the app shows quiet empty/unavailable states and does not fake live alerts.
- Alert coverage varies by region and is not a legal guarantee, police-detection system, or real-time safety system.
- Standard remains the default map mode; Satellite changes map imagery only.
- Top speed ignores invalid/negative GPS speed samples and older trip records show `—` when no top speed was saved.

### Release Positioning

TimeThrottle 1.5.5 adds passive alert and map-mode foundations, saves top-speed context, and simplifies setup while preserving Apple Maps as the ETA-baseline layer and TimeThrottle's Live Drive analysis model.

## v1.5.4 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.4**
>
> - Polishes HUD and Map tab map layout so the map fills the available lower screen area more cleanly
> - Adds a Map tab Options panel for route forecast, Nearby Low Aircraft, voice guidance, speed-limit, and pace details
> - Refreshes optional OpenSky Nearby Low Aircraft data on a conservative interval and removes stale markers
> - Fixes voice picker scrolling by moving selection into a dedicated sheet
> - Persists selected local iOS voice, mute state, and speech speed across launches

### Release Notes

- HUD and Map tab maps keep route polyline, user location, aircraft markers, recenter, and follow behavior intact while reducing unnecessary bottom gaps.
- Map Options keeps route-intelligence details out of the always-visible map view.
- Nearby Low Aircraft remains optional, passive, informational only, and dependent on OpenSky availability; it is not an aviation safety or collision-avoidance system.
- Voice guidance remains local/system-based through AVSpeechSynthesizer and does not use external AI voice services.

### Release Positioning

TimeThrottle 1.5.4 is a polish and reliability release for the v1.5 app structure. It improves map feel, organizes route intelligence in an Options panel, refreshes aircraft data more predictably, and makes voice choice persistent.

## v1.5.3 - April 25, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.3**
>
> - Adds bottom navigation for Drive, HUD, Map, and Trips
> - Adds a dedicated map-first route view with guidance, speed, speed-limit estimate, and recenter support
> - Improves local iOS system voice guidance with best-available English voice selection and clearer speech pacing
> - Adds lightweight HUD voice controls for mute, voice choice, test prompt, and speech speed

### Release Notes

- Drive remains the setup and route-selection entry point.
- HUD remains the focused quick-glance driving dashboard.
- Map is now the larger map-first Live Drive view using Apple Maps route data, speed-limit estimates where available, and the same route/map state.
- Trips is now a first-class bottom-tab entry point for Trip History and trip details.
- Voice guidance remains local/system-based through AVSpeechSynthesizer and does not use external AI voice services.

### Release Positioning

TimeThrottle 1.5.3 makes the app feel more complete with clear bottom navigation and better local system voice guidance while preserving Apple Maps as the ETA-baseline layer and route-data source.

## v1.5.2 - April 25, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.2**
>
> - Removes the user-entered Desired Speed field from Live Drive setup
> - Measures Time Above Speed Limit and Time Below Speed Limit against available OpenStreetMap speed-limit estimates
> - Pauses speed-limit pace accumulation when no estimate is available
> - Clarifies route forecast loading and unavailable wording for WeatherKit-dependent data

### Release Notes

- Live Drive now starts from a route and Apple Maps ETA baseline without requiring a user-entered speed.
- Speed-limit analysis uses available OpenStreetMap estimates only and shows unavailable or unmeasured states when estimates are missing.
- Route forecast UI now uses clearer Route Forecast / Forecast unavailable wording and explains that forecasts are matched to expected arrival times.

### Release Positioning

TimeThrottle 1.5.2 shifts pace analysis from user-entered speed to available OpenStreetMap speed-limit estimates while preserving Apple Maps as the ETA-baseline layer.

## v1.5.1 - April 25, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.1**
>
> - Refines aircraft into passive Nearby Low Aircraft mode
> - Filters OpenSky ADS-B aircraft by distance, recent position, and low-altitude threshold before showing markers
> - Adds structured OpenStreetMap current-road speed-limit estimates with confidence, road name, way ID, and local caching
> - Keeps HUD speed-limit wording careful with Speed Limit / Unavailable states

### Release Notes

- Aircraft data is informational only and does not provide collision avoidance or aviation safety alerts.
- Nearby Low Aircraft defaults to a 10-mile radius and uses a 5,000-foot best-available altitude approximation when OpenSky data is available.
- OpenStreetMap speed limits remain estimates, are cached locally to avoid repeated segment lookups, and show Unavailable when confidence is too low.

### Release Positioning

TimeThrottle 1.5.1 is a targeted route-intelligence refinement release. It keeps Apple Maps as the ETA-baseline layer while making aircraft and speed-limit features quieter, more useful, and more truthful.

## v1.5.0 - April 25, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.0**
>
> - Adds in-app guidance based on Apple Maps route steps
> - Shows next maneuver, distance, mute, off-route, and reroute status in the HUD
> - Adds route weather checkpoints with graceful unavailable handling
> - Adds OpenStreetMap speed-limit estimates where available
> - Adds optional nearby aircraft display using OpenSky ADS-B data

### Release Notes

- Apple Maps remains the route lookup and ETA-baseline layer for trip analysis.
- In-app guidance uses Apple Maps route steps and does not claim Apple-native navigation, lane guidance, or live traffic ownership.
- Route weather is presented as forecast near the route and expected around arrival time.
- Speed limits are shown only as estimates where OpenStreetMap maxspeed data is available.
- Nearby aircraft is optional and depends on OpenSky ADS-B availability.

### Release Positioning

TimeThrottle 1.5.0 adds route intelligence and guidance layers while preserving the Live Drive pace-analysis product model, Trip History, external navigation handoff, and Apple Maps ETA baseline.

## v1.4.3 - April 19, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.4.3**
>
> - Polished the Current Speed HUD card and widened the Avg Spd pill
> - Renamed HUD and result wording around Apple Maps ETA and pace-result metrics
> - Updated Live Drive setup speed-entry wording at that release
> - Consolidated finished-trip and Trip History detail stats into tighter summaries
> - Displays projected arrival in the destination's local time when that time zone is available

### Release Notes

- Polished the Current Speed HUD card and widened the Avg Spd pill
- Renamed HUD and result wording around Apple Maps ETA and pace-result metrics
- Updated Live Drive setup speed-entry wording at that release
- Consolidated finished-trip and Trip History detail stats into tighter summaries
- Displays projected arrival in the destination's local time when that time zone is available

### Release Positioning

TimeThrottle 1.4.3 keeps the app focused on Live Drive, Apple Maps ETA comparison, and tighter trip results without changing the app into a navigation product.

## v1.4.2 - April 16, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.4.2**
>
> - Simplified the app around Live Drive
> - Updated the HUD to focus on Current Speed, ETA, Arrive, Time Saved, and Time Lost
> - Improved the live map with user follow and recenter behavior
> - Removed legacy planning concepts from the product story

### Release Notes

- Simplified the app around Live Drive
- Updated the HUD to focus on Current Speed, ETA, Arrive, Time Saved, and Time Lost
- Improved the live map with user follow and recenter behavior
- Removed legacy planning concepts from the product story
- Kept Trip History and finished-trip results centered on the Apple Maps ETA baseline

### Release Positioning

TimeThrottle 1.4.2 is a Live Drive-only simplification release. Apple Maps remains the route lookup and ETA-baseline layer, Live Drive remains the core experience, and the app continues to avoid claiming built-in turn-by-turn navigation.

## Earlier releases

Earlier release notes are preserved in git history. The current product truth is now Live Drive-focused and no longer includes separate planning features.
