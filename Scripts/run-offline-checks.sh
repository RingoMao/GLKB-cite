#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SDKROOT_VALUE="${SDKROOT_OVERRIDE:-$(xcrun --sdk macosx --show-sdk-path)}"
HOST_ARCHITECTURE="$(uname -m)"
case "$HOST_ARCHITECTURE" in
    arm64 | x86_64) ;;
    *)
        printf 'Unsupported build architecture: %s\n' "$HOST_ARCHITECTURE" >&2
        exit 64
        ;;
esac
TARGET_TRIPLE="$HOST_ARCHITECTURE-apple-macosx13.0"
CHECK_DIR="$(mktemp -d /tmp/glkb-cite-offline.XXXXXX)"
trap 'rm -rf "$CHECK_DIR"' EXIT
export CLANG_MODULE_CACHE_PATH="$CHECK_DIR/clang-module-cache"
export SWIFT_MODULE_CACHE_PATH="$CHECK_DIR/swift-module-cache"

CORE_SOURCES=()
while IFS= read -r -d '' source; do CORE_SOURCES+=("$source"); done \
    < <(find "$PROJECT_DIR/Sources/GLKBCiteCore" -name '*.swift' -print0)

swiftc -warnings-as-errors -sdk "$SDKROOT_VALUE" -target "$TARGET_TRIPLE" \
    -emit-library -emit-module -module-name GLKBCiteCore \
    "${CORE_SOURCES[@]}" \
    -emit-module-path "$CHECK_DIR/GLKBCiteCore.swiftmodule" \
    -o "$CHECK_DIR/libGLKBCiteCore.dylib"

swiftc -warnings-as-errors -sdk "$SDKROOT_VALUE" -target "$TARGET_TRIPLE" \
    -I "$CHECK_DIR" -L "$CHECK_DIR" -lGLKBCiteCore \
    "$PROJECT_DIR/Sources/GLKBCiteMac/System/AccessibilityPermissionManager.swift" \
    "$PROJECT_DIR/Sources/GLKBCiteMac/System/AccessibilitySelectionProvider.swift" \
    "$PROJECT_DIR/Sources/GLKBCiteMac/System/ClipboardCompatibilityCapture.swift" \
    "$PROJECT_DIR/Sources/GLKBCiteMac/System/AutomaticSelectionMonitor.swift" \
    "$PROJECT_DIR/Sources/GLKBCiteMac/System/KeychainGLKBAPIKeyStore.swift" \
    "$SCRIPT_DIR/OfflineChecks.swift" \
    -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    -o "$CHECK_DIR/offline-checks"

"$CHECK_DIR/offline-checks" \
    "$PROJECT_DIR/Tests/GLKBCiteCoreTests/Fixtures/glkb-response.json"
