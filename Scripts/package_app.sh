#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/build"
APP_DIR="$BUILD_ROOT/BabyRecorder.app"
REAL_BUILD_ROOT="/private/tmp/BabyRecorderBuild"
STAGING_ROOT="/private/tmp/BabyRecorderPackage"
STAGED_APP_DIR="$STAGING_ROOT/BabyRecorder.app"
CONTENTS="$STAGED_APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c debug
rm -rf "$BUILD_ROOT"
rm -rf "$REAL_BUILD_ROOT"
rm -rf "$STAGING_ROOT"
mkdir -p "$REAL_BUILD_ROOT"
ln -s "$REAL_BUILD_ROOT" "$BUILD_ROOT"
mkdir -p "$MACOS" "$RESOURCES"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
if [ -d "$ROOT/Sources/BabyRecorder/Resources" ]; then
  cp -R "$ROOT/Sources/BabyRecorder/Resources/"* "$RESOURCES/"
fi
xattr -cr "$STAGED_APP_DIR"
ditto --noextattr --noqtn "$STAGED_APP_DIR" "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "$APP_DIR"
