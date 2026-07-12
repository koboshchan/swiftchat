#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Swiftchat"
BUNDLE_ID="dev.swiftchat.Swiftchat"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/App"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --package-path "$PACKAGE_DIR" --product "$APP_NAME"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS"
cp "$BIN_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements "$ROOT_DIR/Config/Swiftchat.entitlements" "$APP_BUNDLE" >/dev/null

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }

case "$MODE" in
  run) open_app ;;
  --debug|debug) lldb -- "$MACOS/$APP_NAME" ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

