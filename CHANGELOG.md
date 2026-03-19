# Changelog

All notable release-facing changes to **TimeThrottle** should be documented in this file.

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
