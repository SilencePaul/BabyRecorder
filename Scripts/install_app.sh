#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SOURCE="$ROOT/build/BabyRecorder.app"
INSTALL_ROOT="${BABY_RECORDER_INSTALL_DIR:-$HOME/Applications}"
APP_DEST="$INSTALL_ROOT/BabyRecorder.app"

cd "$ROOT"
bash "$ROOT/Scripts/package_app.sh" >/dev/null

mkdir -p "$INSTALL_ROOT"
rm -rf "$APP_DEST"
ditto --noextattr --noqtn "$APP_SOURCE" "$APP_DEST"
xattr -cr "$APP_DEST"
codesign --force --deep --sign - "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"

echo "$APP_DEST"
