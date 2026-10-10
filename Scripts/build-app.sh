#!/bin/bash
#
# Assembles, signs and verifies the GLKB Cite application bundle and, unless
# SKIP_DMG=1, its installer disk image.
#
# Version and build number come from the VERSION file at the repository root
# unless VERSION / BUILD_NUMBER are set in the environment; the values in
# Info.plist are placeholders that this script replaces.
#
# Build products live outside the checkout, in SWIFTPM_SCRATCH_ROOT (default
# ~/Library/Caches/org.glkb.cite/build): Xcode 27's SwiftPM code-signs
# intermediate products, and codesign rejects files that synced folders
# (iCloud Drive, Dropbox, …) keep stamping with extended attributes. The bundle
# is assembled and signed in a private temporary directory for the same
# reason; only the verified artifacts are copied back into .build/app.
#
# Environment:
#   BUILD_MODE=development|distribution   distribution adds the release gates
#   CONFIGURATION=release|debug           UNIVERSAL=1 builds arm64 + x86_64
#   SKIP_DMG=1                            bundle only
#   PIN_DEPENDENCIES=1                    refuse any dependency resolution not
#                                         already recorded in Package.resolved
#   DEVELOPER_ID_APPLICATION              signing identity ("-" = ad hoc)
#   SPARKLE_PUBLIC_KEY / SPARKLE_FEED_URL update channel (both or neither)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

die() {
    printf 'build-app.sh: %s\n' "$*" >&2
    exit 64
}

version_field() {
    sed -n "s/^$1=//p" "$PROJECT_DIR/VERSION" | head -n 1
}

BUILD_MODE="${BUILD_MODE:-development}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-$(version_field VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(version_field BUILD_NUMBER)}"
UNIVERSAL="${UNIVERSAL:-0}"
SKIP_DMG="${SKIP_DMG:-0}"
PIN_DEPENDENCIES="${PIN_DEPENDENCIES:-0}"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
APP_NAME="GLKB Cite"
EXECUTABLE_NAME="GLKBCiteMac"
OUTPUT_ROOT="$PROJECT_DIR/.build/app"
FINAL_APP_PATH="$OUTPUT_ROOT/$APP_NAME.app"
DMG_PATH="$OUTPUT_ROOT/$APP_NAME.dmg"

case "$BUILD_MODE" in
    development | distribution) ;;
    *) die "BUILD_MODE must be development or distribution." ;;
esac

[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] \
    || die "VERSION and BUILD_NUMBER are missing from $PROJECT_DIR/VERSION and the environment."
[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || die "VERSION must contain one to three dot-separated integers."
[[ "$BUILD_NUMBER" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] \
    || die "BUILD_NUMBER must contain one to three dot-separated integers."

if [[ -n "$SPARKLE_PUBLIC_KEY" || -n "$SPARKLE_FEED_URL" ]]; then
    [[ -n "$SPARKLE_PUBLIC_KEY" && -n "$SPARKLE_FEED_URL" ]] \
        || die "SPARKLE_PUBLIC_KEY and SPARKLE_FEED_URL must be supplied together."
    [[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
        || die "SPARKLE_PUBLIC_KEY must be a 32-byte Ed25519 public key encoded as base64."
    [[ "$SPARKLE_FEED_URL" =~ ^https://[^[:space:]]+$ ]] \
        || die "SPARKLE_FEED_URL must be an absolute HTTPS URL without whitespace."
fi

if [[ "$BUILD_MODE" == "distribution" ]]; then
    [[ "$CONFIGURATION" == "release" ]] \
        || die "Distribution builds require CONFIGURATION=release."
    [[ "$UNIVERSAL" == "1" ]] \
        || die "Distribution builds require UNIVERSAL=1."
    [[ "$SKIP_DMG" != "1" ]] \
        || die "Distribution builds must produce a DMG."
    [[ -n "$SIGNING_IDENTITY" && "$SIGNING_IDENTITY" != "-" ]] \
        || die "Distribution builds require DEVELOPER_ID_APPLICATION."
    [[ -n "$SPARKLE_PUBLIC_KEY" && -n "$SPARKLE_FEED_URL" ]] \
        || die "Distribution builds require the signed Sparkle feed key and HTTPS URL."
    PIN_DEPENDENCIES=1
fi

# Fail here, not after a multi-minute build, when the identity is unusable.
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGNING_IDENTITY\"" \
        || die "Signing identity not found in the Keychain: $SIGNING_IDENTITY"
fi

for required in LICENSE NOTICE THIRD-PARTY-NOTICES.txt INSTALL.md; do
    [[ -f "$PROJECT_DIR/$required" ]] || die "Required file is missing from the checkout: $required"
done

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/glkb-cite-app.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP_PATH="$STAGING_ROOT/$APP_NAME.app"
STAGED_DMG_PATH="$STAGING_ROOT/$APP_NAME.dmg"

SCRATCH_ROOT="${SWIFTPM_SCRATCH_ROOT:-$HOME/Library/Caches/org.glkb.cite/build}"
mkdir -p "$SCRATCH_ROOT"
printf 'build-app.sh: %s %s (%s), build products in %s\n' "$APP_NAME" "$VERSION" "$BUILD_NUMBER" "$SCRATCH_ROOT" >&2

common_package_arguments() {
    local arguments=(--package-path "$PROJECT_DIR")
    if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
        arguments+=(--disable-sandbox)
    fi
    if [[ -n "${SWIFTPM_CACHE_PATH:-}" ]]; then
        arguments+=(--cache-path "$SWIFTPM_CACHE_PATH")
    fi
    printf '%s\n' "${arguments[@]}"
}

swift_build() {
    local scratch="$1"
    shift
    local arguments=()
    while IFS= read -r argument; do arguments+=("$argument"); done < <(common_package_arguments)
    if [[ -n "${SDKROOT_OVERRIDE:-}" ]]; then
        arguments+=(--sdk "$SDKROOT_OVERRIDE")
    fi
    if [[ "$PIN_DEPENDENCIES" == "1" ]]; then
        # Fetch exactly what Package.resolved records, then refuse to resolve
        # anything else during the build.
        swift package "${arguments[@]}" --scratch-path "$scratch" resolve
        arguments+=(--disable-automatic-resolution)
    fi
    swift build "${arguments[@]}" --scratch-path "$scratch" "$@"
}

build_current_architecture() {
    local scratch="$SCRATCH_ROOT/current"
    swift_build "$scratch" -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
    swift_build "$scratch" -c "$CONFIGURATION" --show-bin-path
}

build_architecture() {
    local architecture="$1"
    local triple="${architecture}-apple-macosx13.0"
    local scratch="$SCRATCH_ROOT/$architecture"
    swift_build "$scratch" --triple "$triple" -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
    swift_build "$scratch" --triple "$triple" -c "$CONFIGURATION" --show-bin-path
}

mkdir -p "$OUTPUT_ROOT"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"

if [[ "$UNIVERSAL" == "1" ]]; then
    ARM_BIN_DIR="$(build_architecture arm64 | tail -n 1)"
    INTEL_BIN_DIR="$(build_architecture x86_64 | tail -n 1)"
    lipo -create \
        "$ARM_BIN_DIR/$EXECUTABLE_NAME" \
        "$INTEL_BIN_DIR/$EXECUTABLE_NAME" \
        -output "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
    BIN_DIR="$ARM_BIN_DIR"
else
    BIN_DIR="$(build_current_architecture | tail -n 1)"
    cp "$BIN_DIR/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
fi

EXECUTABLE_LOAD_COMMANDS="$(otool -l "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME")"
if [[ "$EXECUTABLE_LOAD_COMMANDS" != *"@executable_path/../Frameworks"* ]]; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' \
        "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/Info.plist" "$INFO_PLIST"
cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/PrivacyInfo.xcprivacy" \
    "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$PROJECT_DIR/THIRD-PARTY-NOTICES.txt" \
    "$APP_PATH/Contents/Resources/THIRD-PARTY-NOTICES.txt"
# Apache-2.0 §4 requires redistributions to carry the license and NOTICE; the
# About panel links the bundled copies.
cp "$PROJECT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE.txt"
cp "$PROJECT_DIR/NOTICE" "$APP_PATH/Contents/Resources/NOTICE.txt"
cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/MenuBarIconTemplate.svg" \
    "$APP_PATH/Contents/Resources/MenuBarIconTemplate.svg"
# plutil takes each value as a single argument, so no character in a URL or
# key can be mistaken for command syntax.
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO_PLIST"

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    plutil -replace SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$INFO_PLIST"
    plutil -replace SUFeedURL -string "$SPARKLE_FEED_URL" "$INFO_PLIST"
fi

SPARKLE_SOURCE="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE_SOURCE" ]] \
    || die "The selected SwiftPM bin directory does not contain Sparkle.framework: $SPARKLE_SOURCE"
/usr/bin/ditto "$SPARKLE_SOURCE" "$APP_PATH/Contents/Frameworks/Sparkle.framework"

# The icon renderer is compiled into and run from staging, never the checkout.
ICON_TOOL="$STAGING_ROOT/render-icon"
ICON_MASTER="$STAGING_ROOT/AppIcon-1024.png"
if [[ -n "${SDKROOT_OVERRIDE:-}" ]]; then
    swiftc -sdk "$SDKROOT_OVERRIDE" "$PROJECT_DIR/Scripts/render-icon.swift" -o "$ICON_TOOL"
else
    swiftc "$PROJECT_DIR/Scripts/render-icon.swift" -o "$ICON_TOOL"
fi
"$ICON_TOOL" "$ICON_MASTER" "$APP_PATH/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleIconFile -string AppIcon "$INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null || die "The generated Info.plist is invalid."

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
INSTALLER_XPC="$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
DOWNLOADER_XPC="$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
AUTOUPDATE_TOOL="$SPARKLE_VERSION_DIR/Autoupdate"
UPDATER_APP="$SPARKLE_VERSION_DIR/Updater.app"

for component in \
    "$INSTALLER_XPC" \
    "$DOWNLOADER_XPC" \
    "$AUTOUPDATE_TOOL" \
    "$UPDATER_APP" \
    "$SPARKLE_FRAMEWORK"
do
    [[ -e "$component" ]] || die "Sparkle signing component is missing: $component"
done

# Files copied out of a synced folder (iCloud Drive, Dropbox, …) carry file
# provider extended attributes that codesign rejects as "detritus". The bundle
# now lives in private temp storage, so one strip keeps it clean.
xattr -cr "$APP_PATH"

sign_sparkle_component() {
    local component="$1"
    if [[ "$SIGNING_IDENTITY" == "-" ]]; then
        codesign --force --options runtime --preserve-metadata=entitlements \
            --sign "$SIGNING_IDENTITY" "$component"
    else
        codesign --force --options runtime --timestamp --preserve-metadata=entitlements \
            --sign "$SIGNING_IDENTITY" "$component"
    fi
}

sign_sparkle_component "$INSTALLER_XPC"
sign_sparkle_component "$DOWNLOADER_XPC"
sign_sparkle_component "$AUTOUPDATE_TOOL"
sign_sparkle_component "$UPDATER_APP"
sign_sparkle_component "$SPARKLE_FRAMEWORK"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --options runtime \
        --entitlements "$PROJECT_DIR/Resources/GLKBCite.entitlements" \
        --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
    codesign --force --options runtime --timestamp \
        --entitlements "$PROJECT_DIR/Resources/GLKBCite.entitlements" \
        --sign "$SIGNING_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$SKIP_DMG" != "1" ]]; then
    DEVELOPER_ID_APPLICATION="$SIGNING_IDENTITY" \
        /bin/bash "$SCRIPT_DIR/package-dmg.sh" "$APP_PATH" "$STAGED_DMG_PATH"
fi

if [[ "$BUILD_MODE" == "distribution" ]]; then
    /bin/bash "$SCRIPT_DIR/verify-release.sh" preflight "$APP_PATH" "$STAGED_DMG_PATH"
elif [[ "$SKIP_DMG" == "1" ]]; then
    EXPECT_UNIVERSAL="$UNIVERSAL" /bin/bash "$SCRIPT_DIR/verify-release.sh" development "$APP_PATH"
else
    EXPECT_UNIVERSAL="$UNIVERSAL" /bin/bash "$SCRIPT_DIR/verify-release.sh" development "$APP_PATH" "$STAGED_DMG_PATH"
fi

# Publish the verified artifacts from staging into the repository build folder.
rm -rf "$FINAL_APP_PATH" "$DMG_PATH"
/usr/bin/ditto "$APP_PATH" "$FINAL_APP_PATH"
if [[ "$SKIP_DMG" != "1" ]]; then
    /usr/bin/ditto "$STAGED_DMG_PATH" "$DMG_PATH"
fi

printf '%s\n' "$FINAL_APP_PATH"
if [[ "$SKIP_DMG" != "1" ]]; then
    printf '%s\n' "$DMG_PATH"
fi
