// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimeThrottle",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "TimeThrottleCore", targets: ["TimeThrottleCore"])
    ],
    targets: [
        .target(
            name: "TimeThrottleCore",
            path: "Sources/Core"
        ),
        .testTarget(
            name: "TimeThrottleCoreTests",
            dependencies: ["TimeThrottleCore"],
            path: "Tests/CoreTests"
        )
    ]
)
