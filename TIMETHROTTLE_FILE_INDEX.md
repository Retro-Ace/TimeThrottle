# TimeThrottle File Index

Last audited date: 2026-04-22

Scope: File and folder index for `/Users/anthonylarosa/CODEX/TimeThrottle` only, based on the current repo contents on disk.

## Repo Boundary

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle`
- What it appears to be for:
  - Standalone Git repo for the TimeThrottle iPhone app.
- Important files inside:
  - `.git/`
  - `AGENTS.md`
  - `README.md`
  - `Package.swift`
  - `TimeThrottle.xcodeproj`
  - `TimeThrottle.xcworkspace`
- Current-use notes:
  - `git rev-parse --show-toplevel` resolves to this repo root, so the audit boundary is clear.

## Repo Rules And Entry Docs

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/`
- What it appears to be for:
  - Human and agent orientation.
- Important files inside:
  - `AGENTS.md`
  - `README.md`
  - `CHANGELOG.md`
  - `privacy-policy.md`
  - `TimeThrottle_Developer_Handoff.md`
  - `TimeThrottle_Master_Project_Doc.md`
  - `TimeThrottle_Full_Project_Breakdown.txt`
- Current-use notes:
  - These files repeat a consistent product story: iPhone Live Drive pace analysis, Apple Maps ETA baseline, and optional navigation handoff.

## Swift Package Definition

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/Package.swift`
- What it appears to be for:
  - Swift Package Manager definition for the core logic layer.
- Important files inside:
  - `Package.swift`
- Current-use notes:
  - Defines `TimeThrottleCore` as a library product.
  - Points the package target at `Sources/Core`.
  - Points the package test target at `Tests/CoreTests`.
  - Does not define the full iOS app target.

## Xcode App Project

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/TimeThrottle.xcodeproj`
- What it appears to be for:
  - Main iOS app project.
- Important files inside:
  - `TimeThrottle.xcodeproj/project.pbxproj`
  - `TimeThrottle.xcodeproj/xcshareddata/xcschemes/TimeThrottle.xcscheme`
  - `TimeThrottle.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- Current-use notes:
  - Contains one native app target named `TimeThrottle`.
  - Pulls source files from `Sources/iOS`, `Sources/Core`, and `Sources/SharedUI`.
  - Uses `Resources/iOS/Info.plist`.
  - Sets iOS deployment target `17.0`, marketing version `2.0`, build `18`, bundle identifier `com.timethrottle.app`, and Swift version `6.0`.

## Workspace Wrapper

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/TimeThrottle.xcworkspace`
- What it appears to be for:
  - Workspace entry that currently wraps the Xcode project.
- Important files inside:
  - `TimeThrottle.xcworkspace/contents.xcworkspacedata`
  - `TimeThrottle.xcworkspace/xcshareddata/xcschemes/xcschememanagement.plist`
- Current-use notes:
  - `contents.xcworkspacedata` points only to `TimeThrottle.xcodeproj`.
  - No extra project references are visible in the workspace file.

## App Source Layout

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/Sources`
- What it appears to be for:
  - Main Swift source tree.
- Important files inside:
  - `Sources/Core/LiveDriveTracker.swift`
  - `Sources/Core/PaceAnalysisMath.swift`
  - `Sources/Core/TripAnalysisEngine.swift`
  - `Sources/Core/TripHistoryStore.swift`
  - `Sources/Core/ScannerModels.swift`
  - `Sources/Core/OpenMHzScannerService.swift`
  - `Sources/SharedUI/RouteComparisonView.swift`
  - `Sources/SharedUI/RouteModels.swift`
  - `Sources/SharedUI/NavigationHandoffService.swift`
  - `Sources/SharedUI/TripHistoryViews.swift`
  - `Sources/SharedUI/LiveDriveHUDView.swift`
  - `Sources/SharedUI/ScannerViewModel.swift`
  - `Sources/SharedUI/ScannerTabView.swift`
  - `Sources/iOS/TimeThrottleApp_iOS.swift`
  - `Sources/iOS/IOSRouteComparisonScreen.swift`
  - `Sources/iOS/RoutePreviewMapView_iOS.swift`
  - `Sources/iOS/LiveDriveHUDMapView_iOS.swift`
- Current-use notes:
  - `Core` is the package-backed logic layer, including scanner models and the OpenMHz-style scanner client.
  - `SharedUI` groups reusable app-facing UI, Scanner UI, and shared models/helpers.
  - `iOS` contains the iPhone app entry and iOS-specific map/screen code.

## Tests

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/Tests`
- What it appears to be for:
  - Core logic tests.
- Important files inside:
  - `Tests/CoreTests/TimeThrottleCoreTests.swift`
  - `Tests/CoreTests/TripAnalysisEngineTests.swift`
  - `Tests/CoreTests/TripHistoryStoreTests.swift`
  - `Tests/CoreTests/ScannerServiceTests.swift`
- Current-use notes:
  - The package file directly connects these tests to the `TimeThrottleCore` target.

## Resources

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/Resources`
- What it appears to be for:
  - Non-code app resources and metadata.
- Important files inside:
  - `Resources/LaunchScreen.storyboard`
  - `Resources/iOS/Info.plist`
  - `Resources/TimeThrottleLogo/TimeThrottle-Logo.png`
  - `Resources/TimeThrottleLogo/TimeThrottle-Logo-Only.png`
- Current-use notes:
  - `Info.plist` contains location permission messaging, background-location mode, background-audio mode, and URL scheme queries for Google Maps and Waze.

## Asset Catalog

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/Assets.xcassets`
- What it appears to be for:
  - Xcode-managed app icon catalog.
- Important files inside:
  - `Assets.xcassets/Contents.json`
  - `Assets.xcassets/AppIcon.appiconset/Contents.json`
  - app icon PNG sizes inside `AppIcon.appiconset/`
- Current-use notes:
  - The asset catalog is included in the Xcode target resource phase.
  - The app icon set includes the expected iOS app icon sizes plus a `1024x1024` image.

## Doc Media Assets

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/assets`
- What it appears to be for:
  - Repo documentation media.
- Important files inside:
  - `assets/timethrottle-banner.jpg`
- Current-use notes:
  - `README.md` references this banner image at the top of the file.

## Screenshots

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/SCREENSHOTS`
- What it appears to be for:
  - Saved simulator screenshots showing the app UI.
- Important files inside:
  - `SCREENSHOTS/Simulator Screenshot - iPhone 17 Pro Max - 2026-04-16 at 23.23.24.png`
  - `SCREENSHOTS/Simulator Screenshot - iPhone 17 Pro Max - 2026-04-16 at 23.24.38.png`
- Current-use notes:
  - Filenames indicate iPhone simulator captures from April 16, 2026.
  - These appear to be review/reference artifacts, not source assets required to build the app.

## Scripts

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/scripts`
- What it appears to be for:
  - Build and packaging helpers.
- Important files inside:
  - `scripts/build_ios_sim.sh`
  - `dist-ios`
- Current-use notes:
  - `scripts/build_ios_sim.sh` builds a simulator `.app` into `dist/iOSSimulator`.
  - The script first tries `xcodebuild`, logs to `dist/iOSSimulator/xcodebuild.log`, and falls back to direct `swiftc` compilation if the Xcode build times out.
  - `dist-ios` is a root script file that appears to be the repo-level entry point for this simulator packaging flow.

## Build Outputs

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/build`
- What it appears to be for:
  - Generated Xcode and export output.
- Important files inside:
  - `build/DerivedData/`
  - `build/TimeThrottle.xcarchive/Info.plist`
  - `build/TimeThrottle-iOS-unsigned.xcarchive/Info.plist`
  - `build/export-appstore/TimeThrottle.ipa`
  - `build/export-appstore/ExportOptions.plist`
  - `build/export-appstore/Packaging.log`
- Current-use notes:
  - This folder contains archive and export artifacts rather than source-of-truth configuration.
  - `.gitignore` marks `build/` as generated output.

## Dist Outputs

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/dist`
- What it appears to be for:
  - Generated simulator distribution output.
- Important files inside:
  - `dist/iOSSimulator/TimeThrottle.app/TimeThrottle`
  - `dist/iOSSimulator/TimeThrottle.app/Info.plist`
  - `dist/iOSSimulator/xcodebuild.log`
- Current-use notes:
  - This matches the packaging path documented in `README.md`.
  - `.gitignore` marks `dist/` as generated output.

## SwiftPM Working State

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/.swiftpm`
- What it appears to be for:
  - Swift Package Manager local workspace state.
- Important files inside:
  - `.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata`
- Current-use notes:
  - Useful only as development context.
  - Not a primary documentation target.

## SwiftPM Build Cache

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/.build`
- What it appears to be for:
  - SwiftPM build products, checkouts, caches, and repositories.
- Important files inside:
  - `.build/arm64-apple-macosx/`
  - `.build/checkouts/`
  - `.build/repositories/`
- Current-use notes:
  - Useful only as generated development context.
  - Not a core repo-orientation folder.

## Git Ignore Rules

- Exact path: `/Users/anthonylarosa/CODEX/TimeThrottle/.gitignore`
- What it appears to be for:
  - Ignore generated build and user-specific workspace data.
- Important files inside:
  - `.gitignore`
- Current-use notes:
  - Ignores `.build/`, `.swiftpm/`, `build/`, `dist/`, and Xcode user-state files.
  - This reinforces the difference between source files and generated/dev artifacts.
