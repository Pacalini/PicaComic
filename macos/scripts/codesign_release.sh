#!/bin/sh
set -eu

APP_PATH="${1:-build/macos/Build/Products/Release/pica_comic.app}"
ENTITLEMENTS_PATH="${2:-macos/Runner/Release.entitlements}"

if [ ! -d "$APP_PATH" ]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

if [ ! -f "$ENTITLEMENTS_PATH" ]; then
  echo "error: entitlements file not found: $ENTITLEMENTS_PATH" >&2
  exit 1
fi

sign_bundle() {
  item="$1"
  if [ -e "$item" ] && [ ! -L "$item" ]; then
    codesign --force --options runtime --timestamp=none --sign - "$item"
  fi
}

FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"

if [ -d "$FRAMEWORKS_DIR" ]; then
  find "$FRAMEWORKS_DIR" -depth \( -name "*.framework" -o -name "*.dylib" -o -name "*.so" \) -print | while IFS= read -r item; do
    sign_bundle "$item"
  done
fi

codesign \
  --force \
  --options runtime \
  --timestamp=none \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign - \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
