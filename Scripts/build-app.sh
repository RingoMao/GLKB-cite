#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_MODE="${BUILD_MODE:-development}"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
UNIVERSAL="${UNIVERSAL:-0}"
SKIP_DMG="${SKIP_DMG:-0}"
SIGNING_IDENTITY="${DEVELOPER_ID_APPLICATION:--}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
APP_NAME="GLKB Cite"
EXECUTABLE_NAME="GLKBCiteMac"
OUTPUT_ROOT="$PROJECT_DIR/.build/app"
APP_PATH="$OUTPUT_ROOT/$APP_NAME.app"
DMG_PATH="$OUTPUT_ROOT/$APP_NAME.dmg"

die() {
    printf 'build-app.sh: %s\n' "$*" >&2
    exit 64
}

case "$BUILD_MODE" in
    development | distribution) ;;
    *) die "BUILD_MODE must be development or distribution." ;;
esac

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
fi

swift_build() {
    local arguments=(--package-path "$PROJECT_DIR")
    if [[ "${SWIFTPM_DISABLE_SANDBOX:-0}" == "1" ]]; then
        arguments+=(--disable-sandbox)
    fi
    if [[ -n "${SDKROOT_OVERRIDE:-}" ]]; then
        arguments+=(--sdk "$SDKROOT_OVERRIDE")
    fi
    if [[ -n "${SWIFTPM_CACHE_PATH:-}" ]]; then
        arguments+=(--cache-path "$SWIFTPM_CACHE_PATH")
    fi
    if [[ "$BUILD_MODE" == "distribution" ]]; then
        arguments+=(--disable-automatic-resolution)
    fi
    swift build "${arguments[@]}" "$@"
}

build_current_architecture() {
    swift_build -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
    swift_build -c "$CONFIGURATION" --show-bin-path
}

build_architecture() {
    local architecture="$1"
    local triple="${architecture}-apple-macosx13.0"
    local scratch="$PROJECT_DIR/.build/$architecture"
    swift_build --scratch-path "$scratch" --triple "$triple" -c "$CONFIGURATION" --product "$EXECUTABLE_NAME"
    swift_build --scratch-path "$scratch" --triple "$triple" -c "$CONFIGURATION" --show-bin-path
}

mkdir -p "$OUTPUT_ROOT"
rm -rf "$APP_PATH"
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

cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/PrivacyInfo.xcprivacy" \
    "$APP_PATH/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$PROJECT_DIR/THIRD-PARTY-NOTICES.txt" \
    "$APP_PATH/Contents/Resources/THIRD-PARTY-NOTICES.txt"
cp "$PROJECT_DIR/Sources/GLKBCiteMac/Resources/MenuBarIconTemplate.svg" \
    "$APP_PATH/Contents/Resources/MenuBarIconTemplate.svg"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP_PATH/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_PATH/Contents/Info.plist"
fi

SPARKLE_SOURCE="$BIN_DIR/Sparkle.framework"
[[ -d "$SPARKLE_SOURCE" ]] \
    || die "The selected SwiftPM bin directory does not contain Sparkle.framework: $SPARKLE_SOURCE"
/usr/bin/ditto "$SPARKLE_SOURCE" "$APP_PATH/Contents/Frameworks/Sparkle.framework"

ICON_TOOL="$OUTPUT_ROOT/render-icon"
ICON_MASTER="$OUTPUT_ROOT/AppIcon-1024.png"
if [[ -n "${SDKROOT_OVERRIDE:-}" ]]; then
    swiftc -sdk "$SDKROOT_OVERRIDE" "$PROJECT_DIR/Scripts/render-icon.swift" -o "$ICON_TOOL"
else
    swiftc "$PROJECT_DIR/Scripts/render-icon.swift" -o "$ICON_TOOL"
fi
"$ICON_TOOL" "$ICON_MASTER" "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_PATH/Contents/Info.plist"

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

if [[ "$SKIP_DMG" == "1" ]]; then
    rm -f "$DMG_PATH"
else
    rm -f "$DMG_PATH"
    DMG_STAGE="$(mktemp -d "$OUTPUT_ROOT/dmg-stage.XXXXXX")"
    cleanup_dmg_stage() {
        rm -rf "$DMG_STAGE"
    }
    trap cleanup_dmg_stage EXIT
    /usr/bin/ditto "$APP_PATH" "$DMG_STAGE/$APP_NAME.app"
    ln -s /Applications "$DMG_STAGE/Applications"
    /usr/bin/ditto "$PROJECT_DIR/INSTALL.md" "$DMG_STAGE/Installation Guide.md"
    [[ -L "$DMG_STAGE/Applications" && "$(readlink "$DMG_STAGE/Applications")" == "/Applications" ]] \
        || die "The installer staging folder is missing its Applications shortcut."
    hdiutil create -volname "$APP_NAME Installer" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null
    cleanup_dmg_stage
    trap - EXIT
    if [[ "$SIGNING_IDENTITY" != "-" ]]; then
        codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
        codesign --verify --verbose=2 "$DMG_PATH"
    fi
fi

if [[ "$BUILD_MODE" == "distribution" ]]; then
    /bin/bash "$SCRIPT_DIR/verify-release.sh" preflight "$APP_PATH" "$DMG_PATH"
elif [[ "$SKIP_DMG" == "1" ]]; then
    EXPECT_UNIVERSAL="$UNIVERSAL" /bin/bash "$SCRIPT_DIR/verify-release.sh" development "$APP_PATH"
else
    EXPECT_UNIVERSAL="$UNIVERSAL" /bin/bash "$SCRIPT_DIR/verify-release.sh" development "$APP_PATH" "$DMG_PATH"
fi

printf '%s\n' "$APP_PATH"
if [[ "$SKIP_DMG" != "1" ]]; then
    printf '%s\n' "$DMG_PATH"
fi
