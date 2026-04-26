# TimeThrottle Agents And Workflow

Last audited date: 2026-04-22

Scope: Plain-English explanation of repo-specific working rules and workflow for `/Users/anthonylarosa/CODEX/TimeThrottle` only.

## What `AGENTS.md` Is Saying

- `AGENTS.md` applies only to the repo rooted at `/Users/anthonylarosa/CODEX/TimeThrottle`.
- It identifies this repo as the iPhone Live Drive app `TimeThrottle`.
- It tells agents to preserve the core product model:
  - Apple Maps route planning and ETA baseline
  - live pace tracking
  - optional navigation handoff
- It tells agents to keep changes tightly scoped and avoid unrelated product pivots or broad UI rewrites unless requested.
- It says generated build, archive, screenshot, and dist artifacts are secondary unless the task is specifically about packaging or release outputs.
- It asks for precise notes and summaries about user-visible behavior, data flow, and verification.

## Plain-English Working Rules

- Stay inside this repo boundary.
- Treat this repo as the TimeThrottle codebase only.
- Do not treat this repo as part of the outer `CODEX` workspace.
- Do not mix this repo with `Super Goode`, `Super Goode App`, or `PhotoCleanupStudio`.
- Keep work narrow and specific.
- Prefer truthful descriptions of what the app actually does today.
- Treat `build/`, `dist/`, `SCREENSHOTS/`, `.build/`, and `.swiftpm/` as context or output folders, not as the main source of product truth.

## How Work In This Repo Should Stay Scoped

- Product truth should come from the current source tree and current docs in this repo.
- The main code-bearing areas are:
  - `Sources/Core`
  - `Sources/SharedUI`
  - `Sources/iOS`
  - `Resources`
  - `Assets.xcassets`
- The main supporting docs are:
  - `README.md`
  - `CHANGELOG.md`
  - `privacy-policy.md`
  - `TimeThrottle_Developer_Handoff.md`
  - `TimeThrottle_Master_Project_Doc.md`
  - `TimeThrottle_Full_Project_Breakdown.txt`
- Generated or user-specific state should not be mistaken for repo design:
  - `build/`
  - `dist/`
  - `.build/`
  - `.swiftpm/`
  - `TimeThrottle.xcworkspace/xcuserdata/`

## How The Repo Appears Intended To Be Worked On

### Product understanding first

- `README.md` is clearly written as the first entry point.
- `TimeThrottle_Developer_Handoff.md` is the shortest practical handoff.
- `TimeThrottle_Master_Project_Doc.md` is the broader long-form reference.
- `TimeThrottle_Full_Project_Breakdown.txt` is the longest plain-text explanation.

### Code structure second

- `Package.swift` isolates the reusable `TimeThrottleCore` logic in `Sources/Core`.
- `TimeThrottle.xcodeproj` assembles the full iOS app target using:
  - `Sources/Core`
  - `Sources/SharedUI`
  - `Sources/iOS`
  - `Resources`
  - `Assets.xcassets`
- `TimeThrottle.xcworkspace` currently sits above the project and points back to it.

### Release and packaging context

- `CHANGELOG.md` is the release-facing change log.
- `scripts/build_ios_sim.sh` is the clearest documented build helper on disk.
- `dist-ios` appears to be the root-level launch point for simulator packaging.
- `build/` contains archive and App Store export artifacts.
- `dist/` contains simulator app output and an `xcodebuild` log.
- `SCREENSHOTS/` appears to preserve UI screenshots for review or handoff context.

## Current Maintenance And Release Workflow Supported By Files

- The current docs consistently reference release `v1.4.3` and build `7`.
- `CHANGELOG.md` provides release-facing notes for `v1.4.3` and `v1.4.2`.
- `README.md` includes a reusable `What's New in v1.4.3` block for GitHub releases, TestFlight notes, and App Store Connect.
- `TimeThrottle.xcodeproj/project.pbxproj` stores the active app version/build values.
- `scripts/build_ios_sim.sh` creates a simulator app in `dist/iOSSimulator/TimeThrottle.app`.
- `build/export-appstore/TimeThrottle.ipa` and related export files show that the repo has been used for archive/export output as well.

## How This Repo Differs From The Surrounding Workspace

- This repo has its own `.git` directory and its own `AGENTS.md`.
- That means it should be treated as its own local authority for repo-specific work.
- The path is outside the `CODEX` workspace root named in the outer instructions.
- The app/product identity here is TimeThrottle only.
- Nothing in the current repo structure suggests this repo is a shared mono-repo or a sibling module of the other named projects.

## Practical Newcomer Workflow

1. Confirm you are in `/Users/anthonylarosa/CODEX/TimeThrottle`.
2. Read `AGENTS.md`.
3. Read `README.md`.
4. Read `TimeThrottle_Developer_Handoff.md`.
5. Inspect `Package.swift` and `TimeThrottle.xcodeproj/project.pbxproj`.
6. Use `Sources/` and `Tests/` to understand code layout.
7. Use `CHANGELOG.md`, `build/`, `dist/`, and `scripts/` only when you need release or packaging context.
