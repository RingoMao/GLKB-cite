#!/bin/bash
#
# Build, sign with Developer ID, notarize, and staple a universal GLKB Cite DMG
# that testers can open with a plain double-click. This is the "tester"
# flavour: Developer ID signed and notarized, but without a Sparkle update
# feed. Use BUILD_MODE=distribution in build-app.sh for public releases.
#
# Version and build number come from the VERSION file; each build handed to
# anyone needs a higher BUILD_NUMBER, and the script refuses one that was
# already tagged. Dependencies are pinned to Package.resolved.
#
# Prerequisites: run ./Scripts/setup-signing.sh once.
# Environment: DEVELOPER_ID_APPLICATION (required when the Keychain holds more
# than one Developer ID Application identity), NOTARY_PROFILE, OUTPUT_DIR.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="${NOTARY_PROFILE:-GLKBCite-Notary}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_DIR/.build/release}"

die() { printf 'release-tester.sh: %s\n' "$*" >&2; exit 1; }

version_field() {
    sed -n "s/^$1=//p" "$PROJECT_DIR/VERSION" | head -n 1
}
VERSION="${VERSION:-$(version_field VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(version_field BUILD_NUMBER)}"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || die "VERSION and BUILD_NUMBER are missing from $PROJECT_DIR/VERSION."
TAG="v$VERSION-build$BUILD_NUMBER"
if git -C "$PROJECT_DIR" tag -l "$TAG" | grep -q .; then
    die "$TAG is already tagged: that build has shipped. Raise BUILD_NUMBER in VERSION first."
fi

IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null \
        | grep 'Developer ID Application' | sed -E 's/^.*"(.*)".*$/\1/' || true)"
    IDENTITY_COUNT="$(printf '%s' "$IDENTITIES" | grep -c . || true)"
    case "$IDENTITY_COUNT" in
        0) die "No Developer ID Application identity. Run ./Scripts/setup-signing.sh first." ;;
        1) IDENTITY="$IDENTITIES" ;;
        *)
            printf 'release-tester.sh: several Developer ID Application identities are installed:\n%s\n' "$IDENTITIES" >&2
            die "Choose one with DEVELOPER_ID_APPLICATION=\"…\"."
            ;;
    esac
fi
security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$IDENTITY\"" \
    || die "Identity not found in Keychain: $IDENTITY"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || die "notarytool profile '$PROFILE' is missing. Run ./Scripts/setup-signing.sh first."

printf 'Signing identity: %s\n' "$IDENTITY"
printf 'Building universal %s (%s)…\n' "$VERSION" "$BUILD_NUMBER"
BUILD_OUTPUT="$(
    DEVELOPER_ID_APPLICATION="$IDENTITY" \
    PIN_DEPENDENCIES=1 UNIVERSAL=1 CONFIGURATION=release VERSION="$VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    "$SCRIPT_DIR/build-app.sh"
)"
APP_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | grep '\.app$' | tail -n 1)"
DMG_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | grep '\.dmg$' | tail -n 1)"
[[ -d "$APP_PATH" && -f "$DMG_PATH" ]] || die "build-app.sh did not report both an .app and a .dmg."

printf 'Notarizing %s…\n' "$APP_PATH"
NOTARY_PROFILE="$PROFILE" NOTARY_BUILD_KIND=tester DEVELOPER_ID_APPLICATION="$IDENTITY" \
    "$SCRIPT_DIR/notarize.sh" "$APP_PATH"

mkdir -p "$OUTPUT_DIR"
FINAL_DMG="$OUTPUT_DIR/GLKB Cite $VERSION.dmg"
/usr/bin/ditto "$DMG_PATH" "$FINAL_DMG"
printf '\nNotarized tester DMG ready:\n  %s\n  SHA-256: %s\n' "$FINAL_DMG" "$(shasum -a 256 "$FINAL_DMG" | cut -d' ' -f1)"
printf 'Testers can double-click it and drag GLKB Cite to Applications; no Gatekeeper workaround needed.\n'
printf '\nRecord the shipped build so it cannot be reused:\n  git tag -a "%s" -m "GLKB Cite %s (%s) tester build" && git push origin "%s"\n' "$TAG" "$VERSION" "$BUILD_NUMBER" "$TAG"
