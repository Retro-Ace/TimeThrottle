# TimeThrottle Setup Overview

Last audited date: 2026-04-22

Scope: Documentation-only audit of the Git repo at `/Users/anthonylarosa/CODEX/TimeThrottle`, which is the TimeThrottle codebase only.

## Repo Purpose

- This repo is its own Git repository rooted at `/Users/anthonylarosa/CODEX/TimeThrottle`.
- `AGENTS.md` says this repo is the iPhone Live Drive app `TimeThrottle`.
- `README.md` describes TimeThrottle as an iPhone pace-analysis app built around Apple Maps route planning and ETA baseline data plus live trip tracking, with a separate Scanner tab for informational public scanner listening.
- The docs consistently describe this repo as an iOS app codebase, not a shared workspace repo and not part of `Super Goode`, `Super Goode App`, or `PhotoCleanupStudio`.

## Start Here

1. Read `README.md` for the product overview and current version/build notes.
2. Read `AGENTS.md` for repo-specific working rules and scope boundaries.
3. Read `TimeThrottle_Developer_Handoff.md` for the shortest current-state handoff.
4. Read `TimeThrottle_Master_Project_Doc.md` for the broader project reference.
5. Use `TIMETHROTTLE_FILE_INDEX.md` and `TIMETHROTTLE_DOCS_MAP.md` for a skimmable repo map.

## What The App Appears To Do

- The app is presented as a Live Drive-focused iPhone app.
- Apple Maps is used for route lookup, autocomplete, route options, and ETA baseline planning.
- During a live drive, the app tracks pace and reports:
  - `Time Above Speed Limit`
  - `Time Below Speed Limit`
  - projected arrival versus the Apple Maps ETA baseline
- The docs repeatedly state that the app is not built-in turn-by-turn navigation.
- `Resources/iOS/Info.plist` shows location permissions, background-location usage, and background-audio support for scanner playback after the user starts audio.

## High-Level Repo Structure

### App and build definition

- `Package.swift`
  - Defines a Swift package named `TimeThrottle`.
  - Exposes a library product `TimeThrottleCore`.
  - Points that package target at `Sources/Core`.
- `TimeThrottle.xcodeproj`
  - Defines the main iOS app target `TimeThrottle`.
  - Includes Swift files from `Sources/Core`, `Sources/SharedUI`, and `Sources/iOS`.
  - Uses `Resources/iOS/Info.plist` and bundles app resources.
- `TimeThrottle.xcworkspace`
  - Currently just references `TimeThrottle.xcodeproj`.
  - Acts as a workspace wrapper, but the file on disk does not show extra projects or packages added to the workspace.

### Main source folders

- `Sources/Core`
  - Core trip tracking, pace math, analysis, history storage logic, scanner models, and OpenMHz-style scanner client.
- `Sources/SharedUI`
  - Shared SwiftUI views, models, layout helpers, navigation handoff support, and Scanner tab UI/view model.
- `Sources/iOS`
  - iOS app entry point and iOS-specific map and screen views.
- `Tests/CoreTests`
  - Package-style tests for core logic.

### Resources and assets

- `Resources`
  - Launch screen, `Info.plist`, and logo image files.
- `Assets.xcassets`
  - App icon catalog for the iOS app target.
- `assets`
  - Repo doc/media asset folder currently used by `README.md` for the banner image.
- `SCREENSHOTS`
  - Simulator screenshots that appear to document the current app UI state.

### Release and packaging areas

- `scripts/build_ios_sim.sh`
  - Builds a simulator app bundle into `dist/iOSSimulator`.
  - Falls back to a direct `swiftc` simulator build if `xcodebuild` times out.
- `dist-ios`
  - Root launcher script file that points to the simulator packaging workflow.
- `build`
  - Generated Xcode build outputs, archives, export logs, and an `.ipa`.
- `dist`
  - Generated simulator app bundle and related build log output.

## Important Docs And Their Roles

- `README.md`
  - Main repo entry point and product summary.
- `CHANGELOG.md`
  - Release-facing change history for current versions.
- `privacy-policy.md`
  - Current privacy and data-flow statement for the app.
- `TimeThrottle_Developer_Handoff.md`
  - Short practical handoff.
- `TimeThrottle_Master_Project_Doc.md`
  - Longer current-state product and project reference.
- `TimeThrottle_Full_Project_Breakdown.txt`
  - Longest plain-text breakdown with team-role framing and repo summary.

## How This Repo Appears Intended To Be Worked On

- Work is expected to stay tightly scoped to the TimeThrottle iPhone app.
- `AGENTS.md` tells agents not to introduce unrelated product pivots or broad UI rewrites unless requested.
- The repo supports two parallel ways of understanding the codebase:
  - Swift Package Manager for the reusable core logic in `Sources/Core`
  - Xcode project/workspace for the full iOS app target and packaging flow
- Generated folders such as `build/`, `dist/`, `.build/`, and `.swiftpm/` are present as development context, but `.gitignore` shows they are not meant to be committed as source-of-truth documentation.

## Quick Orientation Notes

- If someone wants product context first, start with `README.md`.
- If someone wants code structure first, inspect `Package.swift`, `TimeThrottle.xcodeproj/project.pbxproj`, and `Sources/`.
- If someone wants release context first, inspect `CHANGELOG.md`, `build/`, `dist/`, and `scripts/build_ios_sim.sh`.
- If someone wants policy/handoff context first, inspect `privacy-policy.md`, `TimeThrottle_Developer_Handoff.md`, and `TimeThrottle_Master_Project_Doc.md`.
