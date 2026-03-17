#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
IOS_DIST_DIR="$DIST_DIR/iOSSimulator"
APP_NAME="TimeThrottle"
APP_BUNDLE="$IOS_DIST_DIR/$APP_NAME.app"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.timethrottle.app}"
WORKSPACE_PATH="$ROOT_DIR/TimeThrottle.xcworkspace"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
PRODUCT_DIR="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator"
PRODUCT_APP="$PRODUCT_DIR/$APP_NAME.app"

mkdir -p "$IOS_DIST_DIR"

xcodebuild \
    -workspace "$WORKSPACE_PATH" \
    -scheme "$APP_NAME" \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    build

if [[ ! -d "$PRODUCT_APP" ]]; then
    echo "Could not find built simulator app for $APP_NAME at $PRODUCT_APP" >&2
    exit 1
fi

rm -rf "$APP_BUNDLE"
cp -R "$PRODUCT_APP" "$APP_BUNDLE"

plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_BUNDLE/Info.plist"

echo "Created $APP_BUNDLE"
