#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$#" -ne 1 ]]; then
    printf 'Usage: NOTARY_PROFILE=profile %s /path/to/GLKB-Cite.dmg\n' "$0" >&2
    exit 64
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    printf 'NOTARY_PROFILE must name an xcrun notarytool Keychain profile.\n' >&2
    exit 64
fi

ARTIFACT="$1"
if [[ ! -f "$ARTIFACT" ]]; then
    printf 'Artifact not found: %s\n' "$ARTIFACT" >&2
    exit 66
fi
if [[ "$ARTIFACT" != *.dmg ]]; then
    printf 'The notarization artifact must be a signed DMG: %s\n' "$ARTIFACT" >&2
    exit 64
fi

APP_PATH="${APP_PATH_OVERRIDE:-${ARTIFACT%.dmg}.app}"
if [[ ! -d "$APP_PATH" ]]; then
    printf 'Matching application bundle not found: %s\n' "$APP_PATH" >&2
    printf 'Set APP_PATH_OVERRIDE if the app is stored elsewhere.\n' >&2
    exit 66
fi

# NOTARY_BUILD_KIND=release (default) expects a full distribution build with a
# Sparkle feed; NOTARY_BUILD_KIND=tester notarizes a Developer ID signed build
# that has no update channel yet (for sharing with testers).
NOTARY_BUILD_KIND="${NOTARY_BUILD_KIND:-release}"
case "$NOTARY_BUILD_KIND" in
    release) PREFLIGHT_MODE=preflight; POSTFLIGHT_MODE=postflight ;;
    tester) PREFLIGHT_MODE=signed-preflight; POSTFLIGHT_MODE=signed-postflight ;;
    *) printf 'NOTARY_BUILD_KIND must be release or tester.\n' >&2; exit 64 ;;
esac

/bin/bash "$SCRIPT_DIR/verify-release.sh" "$PREFLIGHT_MODE" "$APP_PATH" "$ARTIFACT"

if ! NOTARY_OUTPUT="$(
    xcrun notarytool submit "$ARTIFACT" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --output-format json
)"; then
    printf '%s\n' "$NOTARY_OUTPUT" >&2
    exit 1
fi
printf '%s\n' "$NOTARY_OUTPUT"

NOTARY_STATUS="$(printf '%s' "$NOTARY_OUTPUT" | plutil -extract status raw -o - -)"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
    printf 'Notarization finished with status: %s\n' "$NOTARY_STATUS" >&2
    exit 1
fi

# The accepted DMG contains this exact app signature, so both artifacts receive
# tickets. Stapling the sibling app also permits an offline Gatekeeper check.
xcrun stapler staple "$APP_PATH"
xcrun stapler staple "$ARTIFACT"
xcrun stapler validate "$APP_PATH"
xcrun stapler validate "$ARTIFACT"

/bin/bash "$SCRIPT_DIR/verify-release.sh" "$POSTFLIGHT_MODE" "$APP_PATH" "$ARTIFACT"
