// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimeThrottle",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "TimeThrottle", targets: ["TimeThrottle"])
    ],
    targets: [
        .target(
            name: "TimeThrottleCore",
            path: "Sources/Core"
        ),
        .target(
            name: "TimeThrottleSharedUI",
            dependencies: ["TimeThrottleCore"],
            path: "Sources/SharedUI"
        ),
        .executableTarget(
            name: "TimeThrottle",
            dependencies: ["TimeThrottleCore", "TimeThrottleSharedUI"],
            path: ".",
            exclude: [
                ".build",
                ".gitignore",
                "Assets.xcassets",
                "build",
                "dist-ios",
                "dist-mac",
                "README.md",
                "Tests",
                "dist",
                "iOS icons (AppIcon)",
                "scripts",
                "Sources/.DS_Store",
                "Sources/Core",
                "Sources/SharedUI",
                "Resources/Info.plist",
                "Resources/iOS",
                "TimeThrottle.xcworkspace",
                "TimeThrottle.xcodeproj"
            ],
            sources: [
                "Sources/macOS",
                "Sources/iOS"
            ],
            resources: [
                .copy("Resources/AppIcon"),
                .copy("Resources/LaunchScreen.storyboard"),
                .copy("Resources/TimeThrottleLogo")
            ]
        ),
        .testTarget(
            name: "TimeThrottleCoreTests",
            dependencies: ["TimeThrottleCore"],
            path: "Tests/CoreTests"
        )
    ]
)
