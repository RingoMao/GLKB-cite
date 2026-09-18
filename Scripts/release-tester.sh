#!/bin/bash
#
# Build, sign with Developer ID, notarize, and staple a universal GLKB Cite DMG
# that testers can open with a plain double-click. This is the "tester" flavour:
# Developer ID signed and notarized, but without a Sparkle update feed. Use
# BUILD_MODE=distribution in build-app.sh for public releases.
#
# Prerequisites: run ./Scripts/setup-signing.sh once.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-GLKBCite-Notary}"
VERSION="${VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-6}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/.build/release}"

die() { printf 'release-tester.sh: %s\n' "$*" >&2; exit 1; }

IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' | head -n 1 | sed -E 's/^.*"(.*)".*$/\1/' || true)"
fi
[[ -n "$IDENTITY" ]] || die "No Developer ID Application identity. Run ./Scripts/setup-signing.sh first."
security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$IDENTITY\"" \
    || die "Identity not found in Keychain: $IDENTITY"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$PROFILE' is missing. Run ./Scripts/setup-signing.sh first."

printf 'Signing identity: %s\n' "$IDENTITY"
printf 'Building universal %s (%s)…\n' "$VERSION" "$BUILD_NUMBER"
BUILD_OUTPUT="$(
    DEVELOPER_ID_APPLICATION="$IDENTITY" \
    UNIVERSAL=1 CONFIGURATION=release VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    "$SCRIPT_DIR/build-app.sh"
)"
APP_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | grep '\.app$' | tail -n 1)"
DMG_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | grep '\.dmg$' | tail -n 1)"
[[ -d "$APP_PATH" && -f "$DMG_PATH" ]] || die "build-app.sh did not report both an .app and a .dmg."

printf 'Notarizing %s…\n' "$DMG_PATH"
NOTARY_PROFILE="$PROFILE" NOTARY_BUILD_KIND=tester "$SCRIPT_DIR/notarize.sh" "$DMG_PATH"

mkdir -p "$OUTPUT_DIR"
FINAL_DMG="$OUTPUT_DIR/GLKB Cite $VERSION.dmg"
/usr/bin/ditto "$DMG_PATH" "$FINAL_DMG"
printf '\nNotarized tester DMG ready:\n  %s\n  SHA-256: %s\n' "$FINAL_DMG" "$(shasum -a 256 "$FINAL_DMG" | cut -d' ' -f1)"
printf 'Testers can double-click it and drag GLKB Cite to Applications; no Gatekeeper workaround needed.\n'
