#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ICON_PRODUCT=spis-desktop
APP="$ROOT/.build/Spis.app"
INSTALLED=${SPIS_INSTALL_APP_PATH:-"$HOME/Applications/Spis.app"}
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

swift build --package-path "$ROOT" -c release --product Spis
BIN_DIR=$(swift build --package-path "$ROOT" -c release --show-bin-path)

rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
install -m 0644 "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
if [ -n "${WISENT_RELEASE_VERSION:-}" ]; then
  plutil -replace CFBundleShortVersionString -string "$WISENT_RELEASE_VERSION" "$CONTENTS/Info.plist"
  plutil -replace CFBundleVersion -string "${WISENT_BUILD_NUMBER:-$WISENT_RELEASE_VERSION}" "$CONTENTS/Info.plist"
fi
# The feed URL already exists in this repository, in
# .wisent-desktop-release.json - the release manifest wisent-desktop-update
# reads. Until 2026-08-31 this script stamped SUFeedURL only from
# WISENT_UPDATE_FEED_URL, and never validated it. Whatever App/Info.plist
# happened to carry was what shipped, so the committed plist and the shipped
# bundle drifted apart: App/Info.plist names the appcast, while the installed
# 1.0.0 bundle in ~/Applications has no SUFeedURL key at all. Sparkle with no
# feed URL issues no request, so "Check for Updates…" did nothing at all in
# that build. Stamping from the manifest on every build removes the drift.
#
# The manifest is now the default, the environment variable stays an override
# for a staging feed, a non-HTTPS feed fails the build, and a bundle that would
# ship without a feed URL fails the build instead of being discovered months
# later by a user who never got an update.
RELEASE_MANIFEST="$ROOT/.wisent-desktop-release.json"
UPDATE_FEED_URL=${WISENT_UPDATE_FEED_URL:-}
if [ -z "$UPDATE_FEED_URL" ] && [ -f "$RELEASE_MANIFEST" ]; then
  command -v jq >/dev/null 2>&1 || {
    printf 'jq is required to read %s\n' "$RELEASE_MANIFEST" >&2
    exit 1
  }
  UPDATE_FEED_URL=$(jq -r '.feed_url // empty' "$RELEASE_MANIFEST")
fi
case "$UPDATE_FEED_URL" in
  https://*) ;;
  '')
    printf 'No update feed URL: set WISENT_UPDATE_FEED_URL, or .feed_url in %s. An app with an empty SUFeedURL can never check for updates.\n' "$RELEASE_MANIFEST" >&2
    exit 1 ;;
  *)
    printf 'Update feed must use HTTPS: %s\n' "$UPDATE_FEED_URL" >&2
    exit 1 ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
install -m 0755 "$BIN_DIR/Spis" "$MACOS/Spis"
if [ -f "$ROOT/App/AppIcon.icns" ]; then
  install -m 0644 "$ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  sh "$SCRIPT_DIR/import-brand-icon.sh" "$ICON_PRODUCT" "$RESOURCES/AppIcon.icns"
fi
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
  ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
  if ! otool -l "$MACOS/Spis" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS/Spis"
  fi
fi

IDENTITY=${WISENT_CODESIGN_IDENTITY:-}
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Developer ID Application:/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/ {print $2; exit}')
fi
[ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ] || { echo 'Stable signing identity required' >&2; exit 1; }
if [ -d "$FRAMEWORKS/Sparkle.framework" ]; then
  codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$FRAMEWORKS/Sparkle.framework"
fi
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$MACOS/Spis"
codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"

echo "Built $APP"

[ "${SPIS_INSTALL_AFTER_BUILD:-yes}" = no ] && exit 0
mkdir -p "$(dirname "$INSTALLED")"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$INSTALLED" >/dev/null 2>&1 || true
echo "Installed $INSTALLED"
