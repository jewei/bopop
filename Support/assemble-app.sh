#!/usr/bin/env bash
# Assemble an unsigned Bopop.app from an already-built SwiftPM products directory.
# Both local and release builds use this path so resources cannot drift between them.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <products-directory> <Info.plist> <output.app>" >&2
    exit 2
fi

PRODUCTS_DIR="$1"
PLIST_SOURCE="$2"
APP_PATH="$3"
APP_NAME="Bopop"
RESOURCE_BUNDLE="Bopop_BopopKit.bundle"
SPARKLE_FRAMEWORK="$PRODUCTS_DIR/../artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

# SwiftPM keeps dependency artifacts under the package scratch directory, not
# beside multi-architecture products. Fall back to the repository's standard
# .build location when PRODUCTS_DIR is .build/apple/Products/Release.
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi

for required in \
    "$PRODUCTS_DIR/$APP_NAME" \
    "$PRODUCTS_DIR/$RESOURCE_BUNDLE" \
    "$PLIST_SOURCE" \
    "$SPARKLE_FRAMEWORK"
do
    if [[ ! -e "$required" ]]; then
        echo "error: missing app input: $required" >&2
        exit 1
    fi
done

rm -rf "$APP_PATH"
mkdir -p \
    "$APP_PATH/Contents/MacOS" \
    "$APP_PATH/Contents/Resources" \
    "$APP_PATH/Contents/Frameworks"
cp "$PRODUCTS_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$PLIST_SOURCE" "$APP_PATH/Contents/Info.plist"
cp "$(cd "$(dirname "$0")/.." && pwd)/Resources/AppIcon.icns" \
    "$APP_PATH/Contents/Resources/AppIcon.icns"
RESOURCE_DIRECTORY="$PRODUCTS_DIR/$RESOURCE_BUNDLE"
if [[ -d "$RESOURCE_DIRECTORY/Contents/Resources" ]]; then
    RESOURCE_DIRECTORY="$RESOURCE_DIRECTORY/Contents/Resources"
fi
if [[ ! -f "$RESOURCE_DIRECTORY/emoji.json" ]]; then
    echo "error: emoji.json is missing from $PRODUCTS_DIR/$RESOURCE_BUNDLE" >&2
    exit 1
fi
# Copy the generated resource payload rather than naming every resource here;
# future SwiftPM resources then enter both local and release apps automatically.
cp -R "$RESOURCE_DIRECTORY/." "$APP_PATH/Contents/Resources/"
cp -R "$SPARKLE_FRAMEWORK" "$APP_PATH/Contents/Frameworks/"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
