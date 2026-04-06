#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
IOS_DIST_DIR="$DIST_DIR/iOSSimulator"
APP_NAME="TimeThrottle"
APP_BUNDLE="$IOS_DIST_DIR/$APP_NAME.app"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.timethrottle.app}"
PROJECT_PATH="$ROOT_DIR/TimeThrottle.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
PRODUCT_DIR="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator"
PRODUCT_APP="$PRODUCT_DIR/$APP_NAME.app"
INFO_PLIST_TEMPLATE="$ROOT_DIR/Resources/iOS/Info.plist"
PROJECT_FILE="$ROOT_DIR/TimeThrottle.xcodeproj/project.pbxproj"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET_TRIPLE="${IOS_SIMULATOR_TARGET_TRIPLE:-arm64-apple-ios17.0-simulator}"
XCODEBUILD_TIMEOUT_SECONDS="${XCODEBUILD_TIMEOUT_SECONDS:-90}"
XCODEBUILD_LOG="$IOS_DIST_DIR/xcodebuild.log"
SWIFT_MODULE_CACHE_PATH="${SWIFT_MODULE_CACHE_PATH:-/tmp/timethrottle-swift-module-cache}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/timethrottle-clang-module-cache}"

mkdir -p "$IOS_DIST_DIR"

marketing_version() {
    sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$PROJECT_FILE" | head -n 1
}

build_number() {
    sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$PROJECT_FILE" | head -n 1
}

copy_bundle_metadata() {
    cp "$INFO_PLIST_TEMPLATE" "$APP_BUNDLE/Info.plist"
    plutil -replace CFBundleExecutable -string "$APP_NAME" "$APP_BUNDLE/Info.plist"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Info.plist"
    plutil -replace CFBundleName -string "$APP_NAME" "$APP_BUNDLE/Info.plist"
    plutil -replace CFBundleShortVersionString -string "$(marketing_version)" "$APP_BUNDLE/Info.plist"
    plutil -replace CFBundleVersion -string "$(build_number)" "$APP_BUNDLE/Info.plist"
}

compile_launch_screen() {
    xcrun ibtool \
        --compile "$APP_BUNDLE/LaunchScreen.storyboardc" \
        "$ROOT_DIR/Resources/LaunchScreen.storyboard" \
        --sdk "$SDK_PATH" >/dev/null
}

compile_asset_catalog() {
    xcrun actool \
        "$ROOT_DIR/Assets.xcassets" \
        --compile "$APP_BUNDLE" \
        --platform iphonesimulator \
        --minimum-deployment-target 17.0 \
        --target-device iphone \
        --app-icon AppIcon \
        >/dev/null
}

build_with_xcodebuild() {
    rm -f "$XCODEBUILD_LOG"

    xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$APP_NAME" \
        -destination 'generic/platform=iOS Simulator' \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        build >"$XCODEBUILD_LOG" 2>&1 &
    local build_pid=$!
    local elapsed=0

    while kill -0 "$build_pid" 2>/dev/null; do
        if (( elapsed >= XCODEBUILD_TIMEOUT_SECONDS )); then
            echo "xcodebuild did not finish within ${XCODEBUILD_TIMEOUT_SECONDS}s. Falling back to a direct simulator build." >&2
            kill "$build_pid" 2>/dev/null || true
            wait "$build_pid" 2>/dev/null || true
            return 124
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done

    if ! wait "$build_pid"; then
        cat "$XCODEBUILD_LOG" >&2
        return 1
    fi
}

build_with_swiftc_fallback() {
    local executable_path="$APP_BUNDLE/$APP_NAME"

    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE"
    mkdir -p "$SWIFT_MODULE_CACHE_PATH" "$CLANG_MODULE_CACHE_PATH"

    find "$ROOT_DIR/Sources/Core" "$ROOT_DIR/Sources/SharedUI" "$ROOT_DIR/Sources/iOS" -name '*.swift' -print0 \
        | env CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH" SWIFTC_MODULE_CACHE_PATH="$SWIFT_MODULE_CACHE_PATH" xargs -0 xcrun --sdk iphonesimulator swiftc \
            -target "$TARGET_TRIPLE" \
            -sdk "$SDK_PATH" \
            -module-name "$APP_NAME" \
            -emit-executable \
            -o "$executable_path"

    copy_bundle_metadata
    compile_launch_screen
    compile_asset_catalog || true
    cp "$ROOT_DIR/Resources/TimeThrottleLogo/TimeThrottle.png" "$APP_BUNDLE/TimeThrottle.png"
}

if build_with_xcodebuild; then
    if [[ ! -d "$PRODUCT_APP" ]]; then
        echo "Could not find built simulator app for $APP_NAME at $PRODUCT_APP" >&2
        exit 1
    fi

    rm -rf "$APP_BUNDLE"
    cp -R "$PRODUCT_APP" "$APP_BUNDLE"
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Info.plist"
else
    build_with_swiftc_fallback
fi

echo "Created $APP_BUNDLE"
