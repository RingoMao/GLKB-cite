#!/bin/bash
#
# Packages a built "GLKB Cite.app" into the installer disk image: the app, an
# /Applications shortcut and the Installation Guide, signed when a Developer ID
# identity is given. build-app.sh uses it for the initial DMG and notarize.sh
# rebuilds the DMG from the *stapled* app with it, so both always produce the
# same layout.
#
# Usage: package-dmg.sh "/path/to/GLKB Cite.app" "/path/to/output.dmg"
# Environment:
#   DEVELOPER_ID_APPLICATION  signing identity; unset or "-" leaves the DMG unsigned.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="GLKB Cite"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"

die() {
    printf 'package-dmg.sh: %s\n' "$*" >&2
    exit 64
}

[[ "$#" -eq 2 ]] || die "Usage: $0 /path/to/app /path/to/output.dmg"
APP_PATH="$1"
DMG_PATH="$2"
[[ -d "$APP_PATH" ]] || die "Application bundle not found: $APP_PATH"
[[ "$DMG_PATH" == *.dmg ]] || die "The output path must end in .dmg: $DMG_PATH"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/glkb-cite-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# The guide's Gatekeeper workaround (removing the quarantine flag) applies to
# unsigned test builds only. A notarized build opens with a double-click, and
# the section would train users to bypass Gatekeeper, so it is cut out.
render_guide() {
    local source="$1"
    local target="$2"
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        grep -v '^<!-- unsigned-only:' "$source" > "$target"
    else
        awk '
            /^<!-- unsigned-only:start -->/ { skip = 1; next }
            /^<!-- unsigned-only:end -->/ { skip = 0; next }
            !skip
        ' "$source" > "$target"
    fi
}

/usr/bin/ditto "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
render_guide "$PROJECT_DIR/INSTALL.md" "$STAGE/Installation Guide.md"
[[ -L "$STAGE/Applications" && "$(readlink "$STAGE/Applications")" == "/Applications" ]] \
    || die "The installer staging folder is missing its Applications shortcut."
[[ -s "$STAGE/Installation Guide.md" ]] \
    || die "The Installation Guide rendered empty."

rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME Installer" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi
