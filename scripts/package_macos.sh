#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" != "--skip-build" ]]; then
  bash "$ROOT/apps/macos/build-app.sh"
fi
APP="$ROOT/apps/macos/ChaosCat.app"
ARCH="$(lipo -archs "$APP/Contents/MacOS/ChaosCatMac" | tr ' ' '-')"
STAGE="$ROOT/apps/macos/.build/distribution"
mkdir -p "$ROOT/dist"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/ChaosCat.app"
ln -s /Applications "$STAGE/Applications"
codesign --verify --deep --strict "$STAGE/ChaosCat.app"
hdiutil create -srcfolder "$STAGE" -volname "Chaos Cat" -format ULMO -ov "$ROOT/dist/Chaos-Cat-macOS-$ARCH.dmg"
hdiutil verify "$ROOT/dist/Chaos-Cat-macOS-$ARCH.dmg"
rm -rf "$STAGE"
