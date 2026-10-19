#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/apps/macos/.build"
DIST="$ROOT/dist"
NODE_VERSION="v24.19.0"
case "$(uname -m)" in
  arm64) NODE_ARCH=arm64 ;;
  x86_64) NODE_ARCH=x64 ;;
  *) echo "Unsupported macOS architecture" >&2; exit 1 ;;
esac
NODE_NAME="node-$NODE_VERSION-darwin-$NODE_ARCH"
NODE_DIR="$BUILD/$NODE_NAME"
NODE_TAR="$BUILD/$NODE_NAME.tar.gz"
NODE_SUMS="$BUILD/SHASUMS256-$NODE_VERSION.txt"
NODE_URL="https://nodejs.org/dist/$NODE_VERSION"
mkdir -p "$BUILD" "$DIST"

if [[ "${1:-}" != "--skip-build" ]]; then
  if [[ ! -x "$NODE_DIR/bin/node" || ! -f "$NODE_DIR/LICENSE" ]]; then
    curl --fail --location --retry 3 --output "$NODE_TAR" "$NODE_URL/$NODE_NAME.tar.gz"
    curl --fail --location --retry 3 --output "$NODE_SUMS" "$NODE_URL/SHASUMS256.txt"
    EXPECTED="$(awk -v name="$NODE_NAME.tar.gz" '$2 == name {print $1}' "$NODE_SUMS")"
    [[ -n "$EXPECTED" ]] || { echo "Node.js checksum missing" >&2; exit 1; }
    ACTUAL="$(shasum -a 256 "$NODE_TAR" | awk '{print $1}')"
    [[ "$ACTUAL" == "$EXPECTED" ]] || { echo "Node.js checksum mismatch" >&2; exit 1; }
    tar -xzf "$NODE_TAR" -C "$BUILD" "$NODE_NAME/bin/node" "$NODE_NAME/LICENSE"
  fi
  VSIX="$(python3 "$ROOT/scripts/package_vscode.py")"
  CHAOS_CAT_BUNDLED_NODE="$NODE_DIR/bin/node" \
  CHAOS_CAT_BUNDLED_NODE_LICENSE="$NODE_DIR/LICENSE" \
  CHAOS_CAT_BUNDLED_VSIX="$VSIX" \
    bash "$ROOT/apps/macos/build-app.sh"
fi

APP="$ROOT/apps/macos/ChaosCat.app"
test -x "$APP/Contents/Resources/Runtime/node"
test -f "$APP/Contents/Resources/VSCode/ChaosCat.vsix"
ARCH="$(lipo -archs "$APP/Contents/MacOS/ChaosCatMac" | tr ' ' '-')"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="Chaos-Cat-$VERSION-macOS-$ARCH"
STAGE="$BUILD/distribution"
PKG_ROOT="$STAGE/pkg-root"
DMG_ROOT="$STAGE/dmg-root"
PKG_TMP="$STAGE/$NAME.pkg"
DMG_TMP="$STAGE/$NAME.dmg"
rm -rf "$STAGE"
mkdir -p "$PKG_ROOT/Applications" "$DMG_ROOT"
ditto "$APP" "$PKG_ROOT/Applications/ChaosCat.app"
codesign --verify --deep --strict "$PKG_ROOT/Applications/ChaosCat.app"
COMPONENTS="$STAGE/components.plist"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENTS"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$COMPONENTS"

pkgbuild --root "$PKG_ROOT" --install-location / \
  --identifier com.chaoscat.desktop.installer --version "$VERSION" \
  --component-plist "$COMPONENTS" --scripts "$ROOT/scripts/installer" "$PKG_TMP"
pkgutil --expand "$PKG_TMP" "$STAGE/expanded-pkg"
test -f "$STAGE/expanded-pkg/Payload"
rm -rf "$STAGE/expanded-pkg"

ditto "$APP" "$DMG_ROOT/ChaosCat.app"
ln -s /Applications "$DMG_ROOT/Applications"
ditto "$APP/Contents/Resources/VSCode/ChaosCat.vsix" "$DMG_ROOT/ChaosCat-VSCode.vsix"
cp "$ROOT/scripts/installer/INSTALL.txt" "$DMG_ROOT/安装说明.txt"
codesign --verify --deep --strict "$DMG_ROOT/ChaosCat.app"
hdiutil create -srcfolder "$DMG_ROOT" -volname "Chaos Cat" \
  -format ULMO "$DMG_TMP"
hdiutil verify "$DMG_TMP"

mv -f "$PKG_TMP" "$DIST/$NAME.pkg"
mv -f "$DMG_TMP" "$DIST/$NAME.dmg"
(cd "$DIST" && shasum -a 256 "$NAME.pkg" "$NAME.dmg" > "$NAME.sha256")
echo "Built $DIST/$NAME.pkg and $DIST/$NAME.dmg"
