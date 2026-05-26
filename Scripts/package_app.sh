#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT/build"
APP_DIR="$BUILD_ROOT/BabyRecorder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug
rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
xattr -cr "$BUILD_ROOT"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
