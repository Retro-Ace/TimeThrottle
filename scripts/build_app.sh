#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="TimeThrottle"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_SOURCE="$ROOT_DIR/Resources/Info.plist"
EXECUTABLE_SOURCE="$BUILD_DIR/release/$APP_NAME"
DEBUG_EXECUTABLE_SOURCE="$BUILD_DIR/debug/$APP_NAME"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon/AppIcon.icns"
BRAND_IMAGE_SOURCE="$ROOT_DIR/Resources/TimeThrottleLogo/TimeThrottle.png"

mkdir -p "$DIST_DIR"

swift build -c release --product "$APP_NAME"

if [[ -f "$EXECUTABLE_SOURCE" ]]; then
  EXECUTABLE_PATH="$EXECUTABLE_SOURCE"
elif [[ -f "$DEBUG_EXECUTABLE_SOURCE" ]]; then
  EXECUTABLE_PATH="$DEBUG_EXECUTABLE_SOURCE"
else
  echo "Could not find built executable for $APP_NAME" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"
cp "$PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$BRAND_IMAGE_SOURCE" ]]; then
  cp "$BRAND_IMAGE_SOURCE" "$RESOURCES_DIR/TimeThrottle.png"
fi

for RESOURCE_BUNDLE in "$BUILD_DIR/release"/*.bundle; do
  if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
  fi
done

echo "Created $APP_BUNDLE"
