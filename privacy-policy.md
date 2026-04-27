# Privacy Policy for TimeThrottle

**Effective date:** April 27, 2026

TimeThrottle is an iPhone Live Drive pace-analysis app with a separate Scanner tab for informational public scanner listening. It uses Apple Maps route planning as the route and ETA baseline layer and, when enabled by the user, iPhone location services for live trip tracking, guidance based on route steps, route intelligence features, and nearby scanner discovery.

This policy describes what the current app build uses, how that information is used, and what choices users have.

## Information TimeThrottle Uses

### 1. Location Data

If you use **Live Drive**, TimeThrottle may request access to your device location.

Location is used to:
- measure current speed
- measure distance traveled
- track live trip progress
- estimate projected arrival
- measure the active trip against the selected Apple Maps ETA baseline
- show guidance based on Apple Maps route steps
- check OpenStreetMap speed-limit estimates near the current road
- check nearby low aircraft when the optional aircraft layer is enabled
- check optional camera/enforcement reports near the current location when Enforcement Alerts are enabled and a source is configured; fresh installs enable this passive layer by default, and you can turn it off
- keep the Map tab centered on the current drive when follow mode is active
- find nearby public scanner systems when you use Scanner Nearby

If you choose external navigation handoff during Live Drive, the app may request **Always Location** so tracking can continue while Apple Maps, Google Maps, or Waze is open.

If location access is denied or restricted, Live Drive will not function as intended and Scanner Nearby falls back to Browse.

### 2. Route and Search Information

During Live Drive setup, TimeThrottle may use:
- Current Location as a route start when selected
- typed start and destination addresses
- Apple Maps autocomplete suggestions
- Apple Maps route options
- route distance
- Apple ETA baseline

This information is used to plan the route, display route options, and establish the Apple ETA baseline for the drive. Route geometry may also be used to sample weather checkpoints near the route and to support route-step guidance.

### 3. Locally Stored App Data

TimeThrottle stores some app state on-device using local iOS app storage.

This currently includes:
- your preferred external navigation choice for Live Drive
- your selected local iOS guidance voice, mute state, and speech speed
- your selected map mode
- whether optional aircraft and Enforcement Alerts layers are shown
- completed Live Drive trip history

These local records support handoff selection, local voice guidance preferences, scanner system location caching for Nearby, and Trip History review after a Live Drive ends.

## How TimeThrottle Uses This Information

TimeThrottle uses the information above only to:
- look up routes and baseline ETAs with Apple Maps
- show autocomplete suggestions for route entry
- track a live drive when the user enables location access
- calculate Time Above Speed Limit, Time Below Speed Limit, and projected arrival versus the Apple Maps ETA baseline
- show route-step guidance, route weather, speed-limit estimates, optional nearby low aircraft, and optional Enforcement Alerts when available
- save completed Live Drive trips on-device for later review
- hand off navigation to Apple Maps, Google Maps, or Waze when the user chooses that option
- find nearby public scanner systems when Scanner Nearby is used
- play configured third-party or public scanner feed audio when the user starts Scanner playback

## External Services and Handoff

### Apple Maps

TimeThrottle uses Apple Maps for:
- route lookup
- address/autocomplete resolution
- route options
- ETA baseline planning
- route steps used for in-app guidance

### WeatherKit

TimeThrottle may use WeatherKit to request forecasts near sampled route checkpoints. Weather is presented as forecast near the route and expected around the estimated arrival time at each checkpoint. Weather availability can vary and Live Drive does not depend on weather being available.

### OpenStreetMap

TimeThrottle may query OpenStreetMap-derived maxspeed data to show a speed-limit estimate near the current road. These values are estimates where available and are not a legal guarantee. TimeThrottle may cache recent speed-limit lookup results locally by OpenStreetMap way or approximate road corridor so the app does not constantly refetch the same segment. Time Above Speed Limit and Time Below Speed Limit only use trip segments where an OpenStreetMap speed-limit estimate is available.

### OpenSky ADS-B

If you enable the optional Nearby Low Aircraft layer, TimeThrottle may query OpenSky ADS-B data for aircraft near your current area on a conservative refresh interval. The app filters for nearby, lower-altitude aircraft using the best altitude data available from OpenSky, removes or marks stale data when updates are not fresh, and may show callsign, altitude, speed, heading, approximate distance, and last-updated status when available. This feature is passive, informational only, not an aviation safety or collision-avoidance system, optional, and can fail gracefully if OpenSky data is unavailable.

### Enforcement Alerts

Enforcement Alerts are enabled by default on fresh installs and can be turned off. When enabled, TimeThrottle may use OpenStreetMap Overpass or another configured open-data source for speed-camera, red-light-camera, traffic-camera, and enforcement-report tags near your route or current location. Coverage varies by region and may be unavailable in a given build or area. Alerts are passive and informational only; they are not guaranteed, not legal advice, and not a law-enforcement tracking or detection system. If no source is configured or data is unavailable, TimeThrottle shows a quiet empty/unavailable state rather than fake live alerts.

### Public Scanner Feed Providers

The Scanner tab may request public scanner system lists, latest call metadata, talkgroup metadata, and scanner audio URLs from a configured OpenMHz-style or compatible public scanner feed provider. Scanner may also play a configured direct Live Feed stream when a permitted public or third-party stream URL is bundled for a selected scanner system. Scanner is listening only and independent from Live Drive.

Scanner audio comes from configured third-party or public scanner feed providers. TimeThrottle does not scrape Broadcastify, does not record scanner audio, does not save scanner audio files locally except for normal system playback caching that iOS may perform, does not upload scanner feeds, and does not support user-uploaded scanner feeds. TimeThrottle does not use scanner audio for Live Drive, route warnings, route intelligence, incident prediction, or driving recommendations. Coverage, freshness, metadata, live stream availability, and audio availability vary by provider and system. Scanner playback can continue in the background if the user starts audio.

### Google Maps

If you choose **Google Maps** for Live Drive handoff, TimeThrottle attempts to open Google Maps if it is installed. If it is not installed, the app falls back to a web-based route handoff.

When you choose Google Maps handoff, route information needed for that handoff is passed to Google Maps or its web route at your request. Google’s handling of that information is governed by Google’s own policies, not this one.

### Waze

If you choose **Waze** for Live Drive handoff, TimeThrottle attempts to open Waze if it is installed. If it is not installed, the app falls back to a web-based route handoff.

When you choose Waze handoff, route information needed for that handoff is passed to Waze or its web route at your request. Waze’s handling of that information is governed by its own policies, not this one.

### iOS Share Sheet

If you choose to share a finished trip result, TimeThrottle passes the share text you selected into the standard iOS share sheet. TimeThrottle does not automatically upload completed trips anywhere as part of this flow.

## Data Collection, Accounts, and Sharing

Based on the current app repository and build configuration:

- no user account is required
- no cloud sync is included
- no advertising SDK is included
- no third-party analytics SDK is included
- no crash-reporting SDK is included
- TimeThrottle does not sell personal information
- TimeThrottle does not record scanner audio

## Data Storage

The current app is designed to operate primarily on-device.

The verified on-device data currently stored by the app includes:
- the selected external navigation provider for Live Drive
- local iOS voice guidance preferences
- selected Standard / Satellite map mode
- optional aircraft and Enforcement Alerts visibility choices
- cached approximate scanner system locations used for Scanner Nearby
- completed Live Drive trip history

Route calculations and Live Drive comparisons are otherwise performed in the app during normal use.

## Your Choices

You can:
- deny location access
- change location access later in iPhone Settings
- choose Apple Maps, Google Maps, Waze, or Ask Every Time for Live Drive handoff
- choose Standard or Satellite map mode
- turn optional Enforcement Alerts off or back on
- use Scanner Browse without granting location access for Scanner Nearby
- stop scanner playback at any time
- pause, resume, or end a Live Drive at any time
- delete completed trips from Trip History

If you do not grant the location access needed for Live Drive, TimeThrottle will show a clear permission state and Live Drive tracking will not continue as intended.

## Children’s Privacy

TimeThrottle is not directed to children under 13 and is not intended to knowingly collect personal information from children.

## Security

No electronic storage or transmission method can be guaranteed to be completely secure. This policy reflects the current app build and repository state as of the effective date above.

## Changes to This Policy

If TimeThrottle adds new services or data flows in a future release, this policy should be updated before those changes are released.

## Contact

For support or privacy questions, contact: **fixitall329@gmail.com**
