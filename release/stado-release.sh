#!/bin/sh
# Stado's release pipeline runs this on the darwin builder: the same bundle
# build-app.sh makes for the operator, signed with the Developer ID identity
# the manifest's secret_env hands in, then copied to $WISENT_OUTPUT_DIR, where
# the manifest's stage map reads it. SPIS_INSTALL_AFTER_BUILD=no ends
# build-app.sh before it installs or restarts anything on the builder. The
# bundle's CFBundleVersion is the release version itself, which build-app.sh
# writes when no separate build number is given.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
: "${WISENT_VERSION:?WISENT_VERSION is required}"
: "${WISENT_OUTPUT_DIR:?WISENT_OUTPUT_DIR is required}"
: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY is required}"

WISENT_RELEASE_VERSION="$WISENT_VERSION" \
WISENT_CODESIGN_IDENTITY="$MACOS_SIGN_IDENTITY" \
SPIS_INSTALL_AFTER_BUILD=no \
  sh "$ROOT/release/bundle/build-app.sh"

rm -rf "$WISENT_OUTPUT_DIR/Spis.app"
ditto "$ROOT/.build/Spis.app" "$WISENT_OUTPUT_DIR/Spis.app"
