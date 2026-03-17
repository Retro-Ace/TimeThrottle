# TimeThrottle

A simple macOS SwiftUI app for estimating:

- time saved while driving above the speed limit
- time lost while driving below the speed limit because of traffic

The app supports two calculation modes:

- `Simple`: every minute above the limit counts as saved, every minute below counts as lost
- `Speed-Adjusted`: compares the same segment distance against the posted speed limit

## Run

```bash
swift run TimeThrottle
```

## Build

```bash
swift build
```

## Create A `.app`

```bash
./dist-mac
```

That creates `dist/TimeThrottle.app`.

## Create An iOS Simulator Bundle

```bash
./dist-ios
```

That creates `dist/iOSSimulator/TimeThrottle.app`.

## Xcode

For iOS builds, archives, and TestFlight preparation, open `TimeThrottle.xcworkspace` or `TimeThrottle.xcodeproj` in Xcode.

Do not use `Package.swift` as the primary Xcode entry point for iOS distribution work.

The shared `TimeThrottle` scheme in the Xcode project is the archiveable iPhone app target.
