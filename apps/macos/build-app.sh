#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
APP="$SCRIPT_DIR/ChaosCat.app"
STAGING="$SCRIPT_DIR/.build/ChaosCat-staging.app"
PYTHON="${CHAOS_CAT_PYTHON:-python3}"
MODULE_CACHE="${TMPDIR:-/tmp}/chaos-cat-swift-module-cache"

mkdir -p "$MODULE_CACHE"
# The desktop app is built locally; disabling SwiftPM's nested sandbox avoids
# macOS rejecting manifest/module-cache writes in the restricted launcher.
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swift build --disable-sandbox --package-path "$SCRIPT_DIR" -c release

rm -rf "$STAGING"
mkdir -p "$STAGING/Contents/MacOS" "$STAGING/Contents/Resources"
cp "$BUILD_DIR/release/ChaosCatMac" "$STAGING/Contents/MacOS/ChaosCatMac"
strip -S "$STAGING/Contents/MacOS/ChaosCatMac"
"$PYTHON" "$REPO_ROOT/scripts/package_macos_assets.py" "$STAGING/Contents/Resources"
if [[ -n "${CHAOS_CAT_BUNDLED_NODE:-}" ]]; then
  mkdir -p "$STAGING/Contents/Resources/Runtime"
  cp "$CHAOS_CAT_BUNDLED_NODE" "$STAGING/Contents/Resources/Runtime/node"
  cp "$CHAOS_CAT_BUNDLED_NODE_LICENSE" "$STAGING/Contents/Resources/Runtime/LICENSE"
  chmod 755 "$STAGING/Contents/Resources/Runtime/node"
  codesign --force --sign - "$STAGING/Contents/Resources/Runtime/node"
fi
if [[ -n "${CHAOS_CAT_BUNDLED_VSIX:-}" ]]; then
  mkdir -p "$STAGING/Contents/Resources/VSCode"
  cp "$CHAOS_CAT_BUNDLED_VSIX" "$STAGING/Contents/Resources/VSCode/ChaosCat.vsix"
fi

cat > "$STAGING/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>Chaos Cat</string>
  <key>CFBundleName</key><string>Chaos Cat</string>
  <key>CFBundleIdentifier</key><string>com.chaoscat.desktop</string>
  <key>CFBundleVersion</key><string>0.1.2</string>
  <key>CFBundleShortVersionString</key><string>0.1.2</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>ChaosCatMac</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$STAGING"
codesign --verify --strict "$STAGING"
# Replace the previous package only after compilation and asset validation.
rm -rf "$APP"
mv "$STAGING" "$APP"
echo "Built $APP"
