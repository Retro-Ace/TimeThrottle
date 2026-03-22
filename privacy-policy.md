# Privacy Policy for TimeThrottle

**Effective date:** March 22, 2026

TimeThrottle is an iPhone pace-analysis app. It uses Apple Maps route planning as a baseline and, when enabled by the user, iPhone location services for Live Drive trip tracking.

This policy describes what the current app build uses, how that information is used, and what choices users have.

## Information TimeThrottle Uses

### 1. Location Data

If you use **Live Drive**, TimeThrottle may request access to your device location.

Location is used to:
- Measure current speed
- Measure distance traveled
- Track live trip progress
- Compare the active trip against the selected Apple Maps route baseline

If you choose external navigation handoff during Live Drive, the app may request **Always Location** so tracking can continue while Apple Maps, Google Maps, or Waze is open.

If location access is denied or restricted, Live Drive will not function as intended.

### 2. Route and Search Information

If you use **Route** mode or the setup flow for **Live Drive**, TimeThrottle may use:
- Current Location as a route start when selected
- Typed start and destination addresses
- Apple Maps autocomplete suggestions
- Apple Maps route options
- Route distance
- Apple ETA baseline

This information is used to plan the route, display route options, and compare your pace against a route baseline.

### 3. Manual Inputs

If you use **Manual** mode or pace-analysis inputs elsewhere in the app, TimeThrottle uses values you enter, such as:
- Distance
- Speed
- Trip duration
- MPG
- Fuel price

These values are used only to perform the calculations shown in the app.

### 4. Locally Stored App Data

TimeThrottle stores some app state on-device using local iOS app storage.

This currently includes:
- Your preferred external navigation choice for Live Drive
- Completed Live Drive trip history
- Finished-trip fuel refinement if you choose to enter Observed MPG after a trip

These local records support features such as **Apple Maps**, **Google Maps**, **Waze**, and **Ask Every Time** handoff selection, plus local Trip History review after a Live Drive ends.

## How TimeThrottle Uses This Information

TimeThrottle uses the information above only to:
- Look up routes and baseline ETAs with Apple Maps
- Show autocomplete suggestions for route entry
- Track a live drive when the user enables location access
- Compare pace and trip tradeoffs such as time saved, time under target pace, fuel penalty, and trip balance
- Save completed Live Drive trips on-device for later review
- Hand off navigation to Apple Maps, Google Maps, or Waze when the user chooses that option

## External Services and Handoff

### Apple Maps

TimeThrottle uses Apple Maps for:
- Route lookup
- Address/autocomplete resolution
- Route options
- ETA baseline planning

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

- No user account is required
- No cloud sync is included
- No advertising SDK is included
- No third-party analytics SDK is included
- No crash-reporting SDK is included
- TimeThrottle does not sell personal information

## Data Storage

The current app is designed to operate primarily on-device.

The verified on-device data currently stored by the app includes:
- The selected external navigation provider for Live Drive
- Completed Live Drive trip history
- Optional Observed MPG refinements you enter for finished trips

Route calculations, manual entries, and live comparisons are otherwise performed in the app during normal use.

## Your Choices

You can:
- Use **Manual** mode without enabling location access
- Use **Route** mode without enabling live trip tracking
- Deny location access
- Change location access later in iPhone Settings
- Choose Apple Maps, Google Maps, Waze, or Ask Every Time for Live Drive handoff
- Pause, resume, or end a Live Drive at any time

If you do not grant the location access needed for Live Drive, TimeThrottle will show a clear permission state and Live Drive tracking will not continue as intended.

## Children’s Privacy

TimeThrottle is not directed to children under 13 and is not intended to knowingly collect personal information from children.

## Security

No electronic storage or transmission method can be guaranteed to be completely secure. This policy reflects the current app build and repository state as of the effective date above.

## Changes to This Policy

If TimeThrottle adds new services or data flows in a future release, this policy should be updated before those changes are released.

## Contact

For support or privacy questions, contact: **fixitall329@gmail.com**
