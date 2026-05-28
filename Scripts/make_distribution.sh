#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_ROOT="$ROOT/dist"
DMG_ROOT="$DIST_ROOT/BabyRecorder-DMG"
DMG_PATH="$DIST_ROOT/BabyRecorder.dmg"

cd "$ROOT"

echo "Packaging BabyRecorder.app..."
APP_PATH="$(bash "$ROOT/Scripts/package_app.sh" | tail -n 1)"

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"

ditto --noextattr --noqtn "$APP_PATH" "$DMG_ROOT/BabyRecorder.app"
ln -s /Applications "$DMG_ROOT/Applications"
xattr -cr "$DMG_ROOT"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "BabyRecorder" \
    --window-pos 200 120 \
    --window-size 640 420 \
    --icon-size 96 \
    --icon "BabyRecorder.app" 160 190 \
    --app-drop-link 480 190 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$DMG_ROOT"
else
  hdiutil create \
    -volname "BabyRecorder" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
fi

echo
echo "Distribution image created:"
echo "  $DMG_PATH"
