#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Antigravity Switcher.app"
APP_DIR="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/Antigravity-Switcher-local.dmg"
ZIP_PATH="$DIST_DIR/Antigravity-Switcher-local.zip"
PRODUCT_NAME="AntigravitySwitcherUI"
BUNDLE_EXECUTABLE_NAME="Antigravity Switcher"
CLIENT_ID=${GOOGLE_OAUTH_CLIENT_ID:-}
PACKAGE_CACHE=${ANTIGRAVITY_SWITCHER_BUILD_CACHE:-/tmp/antigravity-switcher-package-cache}

mkdir -p "$PACKAGE_CACHE"
export CLANG_MODULE_CACHE_PATH="$PACKAGE_CACHE"
export SWIFT_MODULECACHE_PATH="$PACKAGE_CACHE"

if [[ -n "${GOOGLE_OAUTH_CLIENT_SECRET:-}" ]]; then
  print -u2 "warning: GOOGLE_OAUTH_CLIENT_SECRET is intentionally not copied into the app bundle"
fi

mkdir -p "$DIST_DIR"

print "Building release executable…"
cd "$PROJECT_DIR"
BIN_DIR=$(swift build -c release --show-bin-path --disable-sandbox)
EXECUTABLE="$BIN_DIR/$PRODUCT_NAME"
if ! swift build -c release --product "$PRODUCT_NAME" --disable-sandbox; then
  if [[ ! -x "$EXECUTABLE" ]]; then
    print -u2 "error: release build failed before producing an executable"
    exit 1
  fi
  print -u2 "warning: release executable exists; continuing without generated dSYM"
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  print -u2 "error: release executable not found: $EXECUTABLE"
  exit 1
fi

case "$APP_DIR" in
  "$DIST_DIR"/*) ;;
  *) print -u2 "error: unsafe app output path"; exit 1 ;;
esac

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/usr/bin/ditto "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$BUNDLE_EXECUTABLE_NAME"
/bin/chmod 755 "$APP_DIR/Contents/MacOS/$BUNDLE_EXECUTABLE_NAME"
/usr/bin/ditto "$PROJECT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/bin/ditto "$PROJECT_DIR/Packaging/PkgInfo" "$APP_DIR/Contents/PkgInfo"

if [[ -n "$CLIENT_ID" ]]; then
  /usr/libexec/PlistBuddy -c "Set :GoogleOAuthClientID $CLIENT_ID" "$APP_DIR/Contents/Info.plist"
else
  print -u2 "warning: GOOGLE_OAUTH_CLIENT_ID is empty; existing profiles work, but Add account will require configuration"
fi

setopt null_glob
RESOURCE_BUNDLES=("$BIN_DIR"/*.bundle(N))
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  /usr/bin/ditto "$bundle" "$APP_DIR/Contents/Resources/${bundle:t}"
done

ASSET_CATALOG="$PROJECT_DIR/Sources/AntigravitySwitcherUI/Resources/Assets.xcassets"
if [[ -d "$ASSET_CATALOG" ]]; then
  ASSET_INFO_DIR=$(mktemp -d "$PACKAGE_CACHE/asset-info.XXXXXX")
  ASSET_INFO="$ASSET_INFO_DIR/asset-info.plist"
  /usr/bin/xcrun actool "$ASSET_CATALOG" \
    --compile "$APP_DIR/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 13.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ASSET_INFO" \
    --warnings --errors --notices
  rm -rf "$ASSET_INFO_DIR"
else
  print -u2 "warning: UI asset catalog not found; Finder may use a generic app icon"
fi

if command -v xattr >/dev/null 2>&1; then
  /usr/bin/xattr -cr "$APP_DIR"
fi

print "Applying local ad-hoc signature…"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$ZIP_PATH"
print "Creating local ZIP…"
ZIP_STAGE_DIR=$(mktemp -d "$DIST_DIR/.zip-stage.XXXXXX")
ZIP_PACKAGE_DIR="$ZIP_STAGE_DIR/Antigravity Switcher"
mkdir -p "$ZIP_PACKAGE_DIR"
/usr/bin/ditto "$APP_DIR" "$ZIP_PACKAGE_DIR/$APP_NAME"
INSTALLER_APP="$ZIP_PACKAGE_DIR/Cài đặt Antigravity Switcher.app"
mkdir -p "$INSTALLER_APP/Contents/MacOS" "$INSTALLER_APP/Contents/Resources"
/usr/bin/xcrun swiftc \
  -parse-as-library \
  -O \
  -framework AppKit \
  "$PROJECT_DIR/Packaging/Installer.swift" \
  -o "$INSTALLER_APP/Contents/MacOS/Antigravity Switcher Installer"
/usr/bin/ditto "$PROJECT_DIR/Packaging/Installer-Info.plist" "$INSTALLER_APP/Contents/Info.plist"
/usr/bin/ditto \
  "$APP_DIR/Contents/Resources/AppIcon.icns" \
  "$INSTALLER_APP/Contents/Resources/InstallerIcon.icns"
/bin/chmod 755 "$INSTALLER_APP/Contents/MacOS/Antigravity Switcher Installer"
/usr/bin/codesign --force --deep --sign - "$INSTALLER_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$ZIP_PACKAGE_DIR" "$ZIP_PATH"
rm -rf "$ZIP_STAGE_DIR"

STAGE_DIR=$(mktemp -d "$DIST_DIR/.dmg-stage.XXXXXX")
cleanup() { rm -rf "$STAGE_DIR" }
trap cleanup EXIT INT TERM
/usr/bin/ditto "$APP_DIR" "$STAGE_DIR/$APP_NAME"
/bin/ln -s /Applications "$STAGE_DIR/Applications"
rm -f "$DMG_PATH"

print "Creating local DMG…"
DMG_READY=false
if /usr/bin/hdiutil create \
    -volname "Antigravity Switcher" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
  DMG_READY=true
else
  print -u2 "warning: DMG creation is unavailable; use the ZIP or .app output"
  rm -f "$DMG_PATH"
fi

print ""
print "Local package ready:"
print "  App: $APP_DIR"
print "  ZIP: $ZIP_PATH"
if [[ "$DMG_READY" == true ]]; then
  print "  DMG: $DMG_PATH"
fi
print ""
print "This build is ad-hoc signed and intended only for this Mac."
