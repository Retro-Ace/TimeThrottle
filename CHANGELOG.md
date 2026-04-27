# Changelog

All notable release-facing changes to **TimeThrottle** should be documented in this file.

## v2.0 - April 26, 2026

### Build 24 True Live Scanner Support

- Keeps marketing version at 2.0 and bumps the build to 24.
- Adds a Live Feed card to Scanner detail above Latest Calls.
- Adds bundled approved-direct-stream configuration for optional live scanner playback, starting empty until approved URLs are provided.
- Keeps Live Feed playback separate from OpenMHz-style Latest Calls replay, with one active AVPlayer mode at a time.
- Keeps Scanner listening-only, with no Broadcastify scraping, no scanner recording, no uploaded feeds, and no Scanner-based Live Drive route warnings or driving recommendations.

### Build 23 Map Always-On and Route-Intelligence Cleanup

- Keeps marketing version at 2.0 and bumps the build to 23.
- Keeps the Map tab available without an active route, with a clean inactive map state and passive nearby layers when location and data are available.
- Clears the active route, guidance, ETA values, and trip controls after End Trip while keeping the Map tab usable.
- Raises the visible Enforcement Alerts cap to 50, keeps the 3.5-mile route-active distance cap, and uses a 50-alert nearby fallback within 3.0 miles when no route is active.
- Refreshes Enforcement Alerts conservatively by route context, elapsed time, and meaningful movement while keeping raw provider results out of rendered map/list UI.
- Removes the detailed Enforcement Alerts list from Map Options so the map markers carry the visual workload.
- Simplifies the navigation app picker to Apple Maps, Google Maps, and Waze, with old Ask Every Time preferences falling back to Apple Maps.
- Scales Route Forecast checkpoints by route distance with a hard maximum of 12 checkpoints for long drives.

### Build 22 Enforcement Alerts Performance / Capping Pass

- Keeps marketing version at 2.0 and bumps the build to 22.
- Caps rendered Enforcement Alerts so the Map marker layer receives no more than 35 route-active alerts and the no-route fallback receives no more than 25 nearby alerts.
- Filters route-active Enforcement Alerts to 3.5 miles, prioritizing route-relevant and ahead-of-travel alerts before nearest-distance and confidence tie-breaks.
- Uses a 3.0-mile nearby-only fallback when no route is active.
- Replaces large raw source totals with capped user-facing wording such as the number of alerts actually being shown within the active distance cap.

### Build 21 Real-Device Fix Pass

- Keeps marketing version at 2.0 and bumps the build to 21.
- Uses the simplest iOS playback audio session for Scanner calls, retries with the same basic playback setup if activation is rejected, and logs exact NSError domain/code details for real-device diagnosis.
- Keeps Scanner latest calls, selected-row playback, and provider/player unavailable states separate from audio-session failures.
- Adds HUD/map marker diagnostics for aircraft and enforcement layers so source counts, annotation counts, and visible-in-viewport counts can be verified on device.
- Registers and raises priority for passive aircraft and enforcement map annotations so real source-backed markers are more reliable at normal driving zoom.
- Broadens the OpenStreetMap Overpass enforcement query to include conservative traffic-camera and traffic-surveillance tags while keeping markers limited to real tagged source data with valid coordinates.

### Build 20 Real-Device Fix Pass

- Keeps marketing version at 2.0 and bumps the build to 20.
- Fixes Scanner playback startup by using a playback-safe AVAudioSession setup without the incompatible HFP option.
- Lets the main Scanner play button start the selected call or first/latest playable call, and keeps each Latest Calls row play button tied to that specific call.
- Adds clearer Scanner diagnostics for device audio-session failure, unsupported or insecure audio URLs, and provider/player failures.
- Cleans WeatherKit unavailable UI so signed-build WeatherDaemon/WDSJWT failures do not appear raw in route forecast cards.
- Adds a TimeThrottle-owned route advisory display path for real WeatherKit advisory data, with Learn More only when a valid URL exists.
- Defaults fresh installs to Daniel for local voice guidance when available, while preserving saved user voice choices and falling back to available English voices.
- Adds an OpenStreetMap Overpass-backed Enforcement Alerts provider path and keeps map icons limited to real tagged source data with valid coordinates.
- Improves passive aircraft and enforcement marker visibility by raising MapKit marker priority without changing map-follow behavior.

### Build 19 Real-Device Fix Pass

- Keeps marketing version at 2.0 and bumps the build to 19.
- Adds the signed WeatherKit entitlement file and clearer WeatherKit request diagnostics for real-device route forecasts.
- Keeps route forecast unavailable details inside Route Forecast / Map Options and keeps the main Map HUD clean when no weather data is available.
- Fixes Scanner latest-call loading so recent calls are not cleared just because talkgroup metadata is unavailable.
- Uses the OpenMHz-style recent calls endpoint for selected systems, improves call decoding for OpenMHz payload fields, and adds clearer scanner provider/decode/audio unavailable states.
- Defaults passive Enforcement Alerts on for fresh installs while preserving any saved user choice, and renders real configured camera/enforcement markers only when enabled and available.
- Renders fresh nearby ADS-B aircraft as passive Map plane markers and clears stale aircraft from the marker layer.

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 2.0**
>
> - Adds a Scanner tab for informational public scanner listening
> - Adds Nearby and Browse scanner system discovery
> - Adds an OpenMHz-style public scanner client for systems, latest calls, and talkgroups
> - Adds separate Latest Calls replay and optional configured Live Feed playback with background audio support
> - Updates location, privacy, and release docs for Scanner
> - Keeps Live Drive, Map driving HUD, Drive, Trips, and route intelligence unchanged

### Release Notes

- Bottom navigation is now Drive / Map / Trips / Scanner.
- Scanner is independent from Live Drive and does not affect driving calculations, route intelligence, or trip results.
- Scanner supports public scanner systems, optional configured Live Feed playback, latest calls, simple play / pause / next-call controls, and graceful unavailable states.
- The scanner service uses a configurable OpenMHz-style base URL so provider configuration can change later.
- TimeThrottle does not scrape Broadcastify, record scanner audio, or support user-uploaded scanner feeds.
- Scanner coverage varies by system and provider; no push alerts or incident prediction are included in v2.0.

### Release Positioning

TimeThrottle 2.0 adds public scanner listening as a separate informational tab while preserving the Map-first Live Drive product model. Apple Maps remains the route lookup and ETA-baseline layer, and Scanner remains a listening-only feature outside Live Drive.

## v1.5.9 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.9**
>
> - Polishes the Map-first driving HUD hierarchy around guidance, controls, recenter, weather, aircraft, and key metrics
> - Keeps WeatherKit unavailable states inside Map Options instead of the main Map
> - Makes the nearest-aircraft bar quieter and more informational
> - Cleans Trips and Trip Detail wording around Apple ETA, speed-limit analysis, distance, average speed, top speed, and speed-limit coverage

### Release Notes

- Map remains the active driving screen for Drive / Map / Trips.
- The bottom Map control card keeps Pause / Resume, End Trip, key metrics, and Options compact and reachable.
- Map Options remains the detail surface for Weather, Aircraft, Enforcement Alerts, Voice Guidance, Speed Limit, Map Mode, and Pace.
- Trips stores completed results with top speed and speed-limit coverage when available.

### Release Positioning

TimeThrottle 1.5.9 is a final map-first driving polish and route-intelligence consolidation release. It keeps Apple Maps as the ETA-baseline layer and treats aircraft, weather, speed-limit, and enforcement data as informational with variable coverage.

## v1.5.8 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.8**
>
> - Turns Nearby Low Aircraft on by default while keeping the Map Options toggle
> - Fixes the Map weather chip so its weather icon renders visibly
> - Simplifies the floating Recenter control to an icon-only button
> - Adds a compact nearest-aircraft bar on Map when nearby aircraft data is available

### Release Notes

- Aircraft remains user-toggleable from Map Options; stored user preference is respected, and fresh installs default to on.
- The weather chip still uses existing route forecast data and hides when weather is unavailable.
- The nearest-aircraft bar shows one closest relevant aircraft with callsign, distance, altitude, and heading when available.

### Release Positioning

TimeThrottle 1.5.8 is a focused Map refinement release. It keeps Drive / Map / Trips and the active Map driving HUD intact while making aircraft and weather glance surfaces clearer.

## v1.5.7 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.7**
>
> - Adds an always-visible floating Recenter control on the Map tab
> - Adds a compact floating weather chip below the route guidance card for quick-glance route conditions

### Release Notes

- The Recenter control uses the existing Map follow/recenter behavior and stays accessible in Standard and Satellite map modes without living inside the bottom control card.
- The weather chip uses existing route forecast data when available, shows a compact icon and temperature, and stays out of the way when forecast data is unavailable.
- Full route forecast details remain in Map Options.

### Release Positioning

TimeThrottle 1.5.7 is a focused Map polish release. It keeps Drive / Map / Trips intact while making the active Map driving HUD easier to recenter and quicker to scan for weather.

## v1.5.6 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.6**
>
> - Simplifies bottom navigation to Drive / Map / Trips
> - Makes the Map tab the primary active driving HUD with direct Pause / Resume and End Trip controls
> - Keeps route intelligence details in Map Options for weather, aircraft, enforcement alerts, voice, speed limit, pace, map mode, average speed, and top speed
> - Cleans up Trips rows and Trip Detail around speed-limit-based results, distance, average speed, and top speed

### Release Notes

- Map now carries the active-drive essentials: route polyline, current location, next maneuver, distance to next maneuver, voice mute, speed, speed-limit estimate, Apple Maps ETA, projected arrival, route distance, miles driven, recenter, Options, Pause / Resume, and End Trip.
- Map Options remains the detail surface for route forecast, Nearby Low Aircraft, Enforcement Alerts, voice guidance, Speed Limit details, pace details, Map Mode, average speed, and top speed.
- Drive remains setup-focused with Current Location start, destination, route selection, route preview, compact navigation app selection, and Start Drive.
- Trips keeps speed-limit-based Above Limit / Below Limit / Vs ETA results visible and adds clean top-speed and distance context when available.

### Release Positioning

TimeThrottle 1.5.6 simplifies the app structure around Drive / Map / Trips. Map is now the primary driving HUD while preserving Apple Maps as the ETA-baseline layer, live tracking, route intelligence, Trip History, and careful safety/enforcement wording.

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
- Alert coverage varies by region and is not a legal guarantee, enforcement-detection system, or real-time safety system.
- Standard remains the default map mode; Satellite changes map imagery only.
- Top speed ignores invalid/negative GPS speed samples and older trip records show `—` when no top speed was saved.

### Release Positioning

TimeThrottle 1.5.5 adds passive alert and map-mode foundations, saves top-speed context, and simplifies setup while preserving Apple Maps as the ETA-baseline layer and TimeThrottle's Live Drive analysis model.

## v1.5.4 - April 26, 2026

### What's New

Use this block for GitHub releases, TestFlight notes, or App Store Connect:

> **TimeThrottle 1.5.4**
>
> - Polishes Map tab layout so the map fills the available lower screen area more cleanly
> - Adds a Map tab Options panel for route forecast, Nearby Low Aircraft, voice guidance, speed-limit, and pace details
> - Refreshes optional OpenSky Nearby Low Aircraft data on a conservative interval and removes stale markers
> - Fixes voice picker scrolling by moving selection into a dedicated sheet
> - Persists selected local iOS voice, mute state, and speech speed across launches

### Release Notes

- Map views keep route polyline, user location, aircraft markers, recenter, and follow behavior intact while reducing unnecessary bottom gaps.
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
> - Adds bottom navigation for Drive, Map, and Trips-era route views
> - Adds a dedicated map-first route view with guidance, speed, speed-limit estimate, and recenter support
> - Improves local iOS system voice guidance with best-available English voice selection and clearer speech pacing
> - Adds lightweight local voice controls for mute, voice choice, test prompt, and speech speed

### Release Notes

- Drive remains the setup and route-selection entry point.
- The focused driving view remains quick-glance.
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
> - Removes the user-entered speed field from Live Drive setup
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
> - Keeps speed-limit wording careful with Speed Limit / Unavailable states

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
> - Shows next maneuver, distance, mute, off-route, and reroute status in the driving view
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
> - Polished the Current Speed driving card and widened the Avg Spd pill
> - Renamed result wording around Apple Maps ETA and pace-result metrics
> - Updated Live Drive setup speed-entry wording at that release
> - Consolidated finished-trip and Trip History detail stats into tighter summaries
> - Displays projected arrival in the destination's local time when that time zone is available

### Release Notes

- Polished the Current Speed driving card and widened the Avg Spd pill
- Renamed result wording around Apple Maps ETA and pace-result metrics
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
> - Updated the driving view to focus on Current Speed, ETA, Arrive, and pace results
> - Improved the live map with user follow and recenter behavior
> - Removed legacy planning concepts from the product story

### Release Notes

- Simplified the app around Live Drive
- Updated the driving view to focus on Current Speed, ETA, Arrive, and pace results
- Improved the live map with user follow and recenter behavior
- Removed legacy planning concepts from the product story
- Kept Trip History and finished-trip results centered on the Apple Maps ETA baseline

### Release Positioning

TimeThrottle 1.4.2 is a Live Drive-only simplification release. Apple Maps remains the route lookup and ETA-baseline layer, Live Drive remains the core experience, and the app continues to avoid claiming built-in turn-by-turn navigation.

## Earlier releases

Earlier release notes are preserved in git history. The current product truth is now Live Drive-focused and no longer includes separate planning features.
