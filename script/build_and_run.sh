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
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
APP_ICON_SOURCE="${SWIFTCHAT_APP_ICON:-Swiftchat.icon}"
if [[ "$APP_ICON_SOURCE" = /* ]]; then
  APP_ICON="$APP_ICON_SOURCE"
else
  APP_ICON="$ROOT_DIR/App/Packaging/$APP_ICON_SOURCE"
fi

if [[ "$MODE" != "package" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build --package-path "$PACKAGE_DIR" --product "$APP_NAME"
BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
cp "$BIN_DIR/$APP_NAME" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS/$APP_NAME"
for resource_bundle in "$BIN_DIR"/*.bundle; do
  [[ -d "$resource_bundle" ]] || continue
  ditto "$resource_bundle" "$RESOURCES/$(basename "$resource_bundle")"
done
if [[ -d "$BIN_DIR/OpenSSL.framework" ]]; then
  ditto "$BIN_DIR/OpenSSL.framework" "$FRAMEWORKS/OpenSSL.framework"
  codesign --force --sign - "$FRAMEWORKS/OpenSSL.framework" >/dev/null
fi

if [[ ! -d "$APP_ICON" ]]; then
  echo "missing app icon: $APP_ICON" >&2
  exit 1
fi
ICON_STAGING_DIR="$(mktemp -d "$DIST_DIR/SwiftchatIconSource.XXXXXX")"
trap 'rm -rf "$ICON_STAGING_DIR"' EXIT
ditto "$APP_ICON" "$ICON_STAGING_DIR/$APP_NAME.icon"
ICON_PARTIAL_PLIST="$DIST_DIR/SwiftchatIcon-Info.plist"
xcrun actool \
  --compile "$RESOURCES" \
  --platform macosx \
  --minimum-deployment-target 27.0 \
  --app-icon "$APP_NAME" \
  --output-partial-info-plist "$ICON_PARTIAL_PLIST" \
  --warnings --notices --errors \
  "$ICON_STAGING_DIR/$APP_NAME.icon"
rm -f "$ICON_PARTIAL_PLIST"

cat >"$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>$APP_NAME</string>
  <key>CFBundleIconName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>27.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Swiftchat uses your microphone when you join a voice call.</string>
  <key>NSCameraUsageDescription</key><string>Swiftchat uses your camera when you enable video in a call.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --entitlements "$ROOT_DIR/Config/Swiftchat.entitlements" "$APP_BUNDLE" >/dev/null

open_app() { /usr/bin/open -n "$APP_BUNDLE"; }
open_offline_app() { /usr/bin/open -n "$APP_BUNDLE" --args --offline; }
open_long_server_demo() { /usr/bin/open -n "$APP_BUNDLE" --args --offline --demo-long-server-list; }

case "$MODE" in
  package) ;;
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
    # Verification must never touch a stored Discord credential or the live API.
    open_offline_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --offline|offline|--demo|demo) open_offline_app ;;
  --demo-long-server-list|demo-long-server-list) open_long_server_demo ;;
  *) echo "usage: $0 [package|run|--offline|--demo (alias)|--demo-long-server-list|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
