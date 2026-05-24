#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_LINK="$ROOT/build"
REAL_BUILD_ROOT="${TMPDIR:-/tmp}/BabyRecorder-build"
APP_DIR="$BUILD_LINK/BabyRecorder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug
rm -rf "$REAL_BUILD_ROOT"
mkdir -p "$REAL_BUILD_ROOT"
rm -rf "$BUILD_LINK"
ln -s "$REAL_BUILD_ROOT" "$BUILD_LINK"
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
