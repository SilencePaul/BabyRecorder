#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/build/BabyRecorder.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
swift build -c debug
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp .build/debug/BabyRecorder "$MACOS/BabyRecorder"
cp Info.plist "$CONTENTS/Info.plist"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
