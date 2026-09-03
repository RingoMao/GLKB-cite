#!/bin/bash

set -euo pipefail

usage() {
    printf 'Usage:\n' >&2
    printf '  %s development /path/to/GLKB-Cite.app [/path/to/GLKB-Cite.dmg]\n' "$0" >&2
    printf '  %s preflight /path/to/GLKB-Cite.app /path/to/GLKB-Cite.dmg\n' "$0" >&2
    printf '  %s postflight /path/to/GLKB-Cite.app /path/to/GLKB-Cite.dmg\n' "$0" >&2
    exit 64
}

fail() {
    printf 'verify-release.sh: %s\n' "$*" >&2
    exit 1
}

[[ "$#" -ge 2 && "$#" -le 3 ]] || usage

MODE="$1"
APP_PATH="$2"
DMG_PATH="${3:-}"
EXPECTED_SPARKLE_VERSION="2.9.5"

case "$MODE" in
    development | preflight | postflight) ;;
    *) usage ;;
esac

if [[ "$MODE" != "development" && -z "$DMG_PATH" ]]; then
    usage
fi

[[ -d "$APP_PATH" ]] || fail "Application bundle not found: $APP_PATH"
if [[ -n "$DMG_PATH" ]]; then
    [[ -f "$DMG_PATH" ]] || fail "Disk image not found: $DMG_PATH"
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
PRIVACY_MANIFEST="$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
NOTICES="$APP_PATH/Contents/Resources/THIRD-PARTY-NOTICES.txt"
MENU_BAR_ICON="$APP_PATH/Contents/Resources/MenuBarIconTemplate.svg"
MAIN_EXECUTABLE="$APP_PATH/Contents/MacOS/GLKBCiteMac"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
SPARKLE_INFO="$SPARKLE_VERSION_DIR/Resources/Info.plist"

require_file() {
    [[ -f "$1" ]] || fail "Required file is missing: $1"
}

plist_value() {
    local plist="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null
}

assert_universal() {
    local binary="$1"
    local architectures
    architectures="$(lipo -archs "$binary" 2>/dev/null)" \
        || fail "Could not inspect binary architectures: $binary"
    [[ " $architectures " == *" arm64 "* ]] \
        || fail "arm64 slice is missing from $binary"
    [[ " $architectures " == *" x86_64 "* ]] \
        || fail "x86_64 slice is missing from $binary"
}

require_file "$INFO_PLIST"
require_file "$PRIVACY_MANIFEST"
require_file "$NOTICES"
require_file "$MENU_BAR_ICON"
require_file "$MAIN_EXECUTABLE"
require_file "$SPARKLE_INFO"

plutil -lint "$INFO_PLIST" "$PRIVACY_MANIFEST" >/dev/null \
    || fail "Info.plist or PrivacyInfo.xcprivacy is invalid."

[[ "$(plist_value "$INFO_PLIST" CFBundleIdentifier)" == "org.glkb.cite" ]] \
    || fail "Unexpected CFBundleIdentifier."
[[ "$(plist_value "$INFO_PLIST" CFBundleDisplayName)" == "GLKB Cite" ]] \
    || fail "Unexpected CFBundleDisplayName."
[[ "$(plist_value "$INFO_PLIST" CFBundleExecutable)" == "GLKBCiteMac" ]] \
    || fail "Unexpected CFBundleExecutable."
[[ "$(plist_value "$INFO_PLIST" LSMinimumSystemVersion)" == "13.0" ]] \
    || fail "LSMinimumSystemVersion must remain 13.0."
[[ "$(plist_value "$INFO_PLIST" SURequireSignedFeed)" == "true" ]] \
    || fail "SURequireSignedFeed must be enabled."
[[ "$(plist_value "$INFO_PLIST" SUVerifyUpdateBeforeExtraction)" == "true" ]] \
    || fail "SUVerifyUpdateBeforeExtraction must be enabled."

SHORT_VERSION="$(plist_value "$INFO_PLIST" CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_value "$INFO_PLIST" CFBundleVersion)"
[[ "$SHORT_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || fail "CFBundleShortVersionString has an invalid release format."
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || fail "CFBundleVersion has an invalid release format."

[[ "$(plist_value "$SPARKLE_INFO" CFBundleShortVersionString)" == "$EXPECTED_SPARKLE_VERSION" ]] \
    || fail "The packaged Sparkle version is not $EXPECTED_SPARKLE_VERSION."
grep -Fq "Sparkle $EXPECTED_SPARKLE_VERSION" "$NOTICES" \
    || fail "Third-party notices do not identify Sparkle $EXPECTED_SPARKLE_VERSION."
grep -Fq "Copyright (c) 2006-2013 Andy Matuschak." "$NOTICES" \
    || fail "The complete Sparkle copyright notice is missing."
grep -Fq "SUSignatureVerifier.m:" "$NOTICES" \
    || fail "The bundled-component notices from Sparkle are incomplete."

EXECUTABLE_LOAD_COMMANDS="$(otool -l "$MAIN_EXECUTABLE")"
if [[ "$EXECUTABLE_LOAD_COMMANDS" != *"@executable_path/../Frameworks"* ]]; then
    fail "The application executable is missing the embedded-framework rpath."
fi

MACH_O_BINARIES=(
    "$MAIN_EXECUTABLE"
    "$SPARKLE_VERSION_DIR/Sparkle"
    "$SPARKLE_VERSION_DIR/Autoupdate"
    "$SPARKLE_VERSION_DIR/Updater.app/Contents/MacOS/Updater"
    "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc/Contents/MacOS/Installer"
    "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
)

for binary in "${MACH_O_BINARIES[@]}"; do
    require_file "$binary"
done

if [[ "$MODE" != "development" || "${EXPECT_UNIVERSAL:-0}" == "1" ]]; then
    for binary in "${MACH_O_BINARIES[@]}"; do
        assert_universal "$binary"
    done
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH" \
    || fail "The application code signature is invalid."

AUTOUPDATE_ENTITLEMENTS="$(codesign -d --entitlements :- "$SPARKLE_VERSION_DIR/Autoupdate" 2>/dev/null)" \
    || fail "Could not inspect Sparkle Autoupdate entitlements."
printf '%s\n' "$AUTOUPDATE_ENTITLEMENTS" \
    | grep -q '<string>org.sparkle-project.Sparkle.Autoupdate</string>' \
    || fail "Sparkle Autoupdate lost its application-identifier entitlement."

if LC_ALL=C grep -aERq 'glkb_[[:alnum:]_-]{12,}' "$APP_PATH"; then
    fail "The application bundle appears to contain a GLKB credential."
fi
if LC_ALL=C grep -aERq 'example\.test/ask' "$APP_PATH"; then
    fail "The application bundle contains a test credential or network fixture."
fi
REMOVED_BACKEND_PATTERN='h''irn|h''irn-literature-api|askh''irn'
if LC_ALL=C grep -aERqi "$REMOVED_BACKEND_PATTERN" "$APP_PATH"; then
    fail "The citation-only bundle contains a removed backend component."
fi
SERVICES_XML="$(plutil -extract NSServices xml1 -o - "$INFO_PLIST")"
[[ "$(printf '%s' "$SERVICES_XML" | grep -c '<key>NSMessage</key>')" == "1" ]] \
    || fail "The bundle must expose exactly one macOS Service."
printf '%s' "$SERVICES_XML" | grep -q '<string>findGLKBCitations</string>' \
    || fail "The citation Service selector is missing."
printf '%s' "$SERVICES_XML" | grep -q '<string>Find Citations with GLKB Cite</string>' \
    || fail "The citation Service name is incorrect."

if [[ -n "$DMG_PATH" ]]; then
    hdiutil verify "$DMG_PATH" >/dev/null \
        || fail "The disk image checksum is invalid."
fi

if [[ "$MODE" == "development" ]]; then
    printf 'Development bundle verification passed: %s\n' "$APP_PATH"
    exit 0
fi

PUBLIC_KEY="$(plist_value "$INFO_PLIST" SUPublicEDKey)" \
    || fail "SUPublicEDKey is missing from the distribution bundle."
FEED_URL="$(plist_value "$INFO_PLIST" SUFeedURL)" \
    || fail "SUFeedURL is missing from the distribution bundle."
[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
    || fail "SUPublicEDKey is not a 32-byte base64 Ed25519 public key."
[[ "$FEED_URL" =~ ^https://[^[:space:]]+$ ]] \
    || fail "SUFeedURL is not an absolute HTTPS URL."

APP_SIGNATURE="$(codesign -dvvv "$APP_PATH" 2>&1)" \
    || fail "Could not inspect the application signature."
printf '%s\n' "$APP_SIGNATURE" | grep -q '^Authority=Developer ID Application:' \
    || fail "The app is not signed by a Developer ID Application certificate."
printf '%s\n' "$APP_SIGNATURE" | grep -q 'flags=.*runtime' \
    || fail "The app signature does not enable Hardened Runtime."
printf '%s\n' "$APP_SIGNATURE" | grep -q '^Timestamp=' \
    || fail "The app signature does not contain a trusted timestamp."
APP_TEAM="$(printf '%s\n' "$APP_SIGNATURE" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
[[ -n "$APP_TEAM" && "$APP_TEAM" != "not set" ]] \
    || fail "The app signature has no TeamIdentifier."

SIGNED_COMPONENTS=(
    "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
    "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
    "$SPARKLE_VERSION_DIR/Autoupdate"
    "$SPARKLE_VERSION_DIR/Updater.app"
    "$SPARKLE_FRAMEWORK"
)
for component in "${SIGNED_COMPONENTS[@]}"; do
    COMPONENT_SIGNATURE="$(codesign -dvvv "$component" 2>&1)" \
        || fail "Could not inspect the signature for $component"
    COMPONENT_TEAM="$(printf '%s\n' "$COMPONENT_SIGNATURE" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
    [[ "$COMPONENT_TEAM" == "$APP_TEAM" ]] \
        || fail "Sparkle component is not signed by the app team: $component"
done

codesign --verify --verbose=2 "$DMG_PATH" \
    || fail "The disk image signature is invalid."
DMG_SIGNATURE="$(codesign -dvvv "$DMG_PATH" 2>&1)" \
    || fail "Could not inspect the disk image signature."
printf '%s\n' "$DMG_SIGNATURE" | grep -q '^Authority=Developer ID Application:' \
    || fail "The disk image is not signed by a Developer ID Application certificate."
DMG_TEAM="$(printf '%s\n' "$DMG_SIGNATURE" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
[[ "$DMG_TEAM" == "$APP_TEAM" ]] \
    || fail "The app and disk image are signed by different teams."

if [[ "$MODE" == "preflight" ]]; then
    printf 'Distribution preflight passed: %s\n' "$DMG_PATH"
    exit 0
fi

xcrun stapler validate "$APP_PATH" \
    || fail "The application does not have a valid stapled notarization ticket."
xcrun stapler validate "$DMG_PATH" \
    || fail "The disk image does not have a valid stapled notarization ticket."
spctl --assess --type execute --verbose=4 "$APP_PATH" \
    || fail "Gatekeeper rejected the application."
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH" \
    || fail "Gatekeeper rejected the disk image."

printf 'Notarized release verification passed: %s\n' "$DMG_PATH"
