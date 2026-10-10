#!/bin/bash
#
# Notarizes a Developer ID signed GLKB Cite build so Gatekeeper accepts it on
# any Mac, including one that cannot reach Apple to look up a ticket:
#
#   1. the .app is submitted (as a zip) and its ticket is stapled to the bundle;
#   2. the installer DMG is rebuilt from the stapled app and signed;
#   3. the DMG is submitted and stapled;
#   4. verify-release.sh postflight checks both tickets and Gatekeeper.
#
# Stapling a DMG never staples the app inside it, which is why the app goes
# first and the DMG is rebuilt afterwards.
#
# Usage:
#   NOTARY_PROFILE=profile notarize.sh "/path/to/GLKB Cite.app"
#   NOTARY_PROFILE=profile notarize.sh "/path/to/GLKB Cite.dmg"   (app = sibling .app)
# Environment:
#   NOTARY_BUILD_KIND=release|tester   release (default) expects a Sparkle feed;
#                                      tester verifies a feed-less build
#   APP_PATH_OVERRIDE                  the app, when it is not beside the DMG
#   DEVELOPER_ID_APPLICATION           identity for the rebuilt DMG (default:
#                                      the identity that signed the app)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

die() {
    printf 'notarize.sh: %s\n' "$*" >&2
    exit "${2:-1}"
}

if [[ "$#" -ne 1 ]]; then
    printf 'Usage: NOTARY_PROFILE=profile %s "/path/to/GLKB Cite.app" | "/path/to/GLKB Cite.dmg"\n' "$0" >&2
    exit 64
fi
[[ -n "${NOTARY_PROFILE:-}" ]] \
    || die "NOTARY_PROFILE must name an xcrun notarytool Keychain profile." 64

TARGET="$1"
case "$TARGET" in
    *.app)
        APP_PATH="$TARGET"
        DMG_PATH="${TARGET%.app}.dmg"
        ;;
    *.dmg)
        DMG_PATH="$TARGET"
        APP_PATH="${APP_PATH_OVERRIDE:-${TARGET%.dmg}.app}"
        ;;
    *) die "The artifact must be a .app bundle or its .dmg: $TARGET" 64 ;;
esac
[[ -d "$APP_PATH" ]] \
    || die "Application bundle not found: $APP_PATH (set APP_PATH_OVERRIDE if it is stored elsewhere)." 66

NOTARY_BUILD_KIND="${NOTARY_BUILD_KIND:-release}"
case "$NOTARY_BUILD_KIND" in
    release) PREFLIGHT_MODE=preflight; POSTFLIGHT_MODE=postflight ;;
    tester) PREFLIGHT_MODE=signed-preflight; POSTFLIGHT_MODE=signed-postflight ;;
    *) die "NOTARY_BUILD_KIND must be release or tester." 64 ;;
esac

IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(codesign -dvv "$APP_PATH" 2>&1 \
        | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -n 1)"
fi
[[ -n "$IDENTITY" ]] \
    || die "The app is not signed with a Developer ID Application identity: $APP_PATH"

# The preflight inspects the DMG as well; package one when only the app exists.
if [[ ! -f "$DMG_PATH" ]]; then
    DEVELOPER_ID_APPLICATION="$IDENTITY" /bin/bash "$SCRIPT_DIR/package-dmg.sh" "$APP_PATH" "$DMG_PATH"
fi
/bin/bash "$SCRIPT_DIR/verify-release.sh" "$PREFLIGHT_MODE" "$APP_PATH" "$DMG_PATH"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/glkb-cite-notarize.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# Submits one artifact and fails unless Apple accepted it.
submit() {
    local artifact="$1"
    local output status
    if ! output="$(
        xcrun notarytool submit "$artifact" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait \
            --output-format json
    )"; then
        printf '%s\n' "$output" >&2
        return 1
    fi
    printf '%s\n' "$output"
    status="$(printf '%s' "$output" | plutil -extract status raw -o - -)"
    if [[ "$status" != "Accepted" ]]; then
        printf 'Notarization of %s finished with status: %s\n' "$artifact" "$status" >&2
        return 1
    fi
}

printf 'Notarizing the application bundle…\n'
APP_ARCHIVE="$WORK_DIR/$(basename "$APP_PATH").zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ARCHIVE"
submit "$APP_ARCHIVE"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

printf 'Rebuilding the installer disk image from the stapled app…\n'
DEVELOPER_ID_APPLICATION="$IDENTITY" /bin/bash "$SCRIPT_DIR/package-dmg.sh" "$APP_PATH" "$DMG_PATH"

printf 'Notarizing the disk image…\n'
submit "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

/bin/bash "$SCRIPT_DIR/verify-release.sh" "$POSTFLIGHT_MODE" "$APP_PATH" "$DMG_PATH"
