#!/usr/bin/env bash
# Usage: Support/release.sh [version] [build]
#   version  e.g. 0.2.0  (default: CFBundleShortVersionString in Support/Info.plist)
#   build    e.g. 42     (default: git commit count — `git rev-list --count HEAD`)
#
# Prerequisites:
#   • Developer ID Application certificate in the login keychain
#   • xcrun notarytool credentials stored: notarytool store-credentials "notarytool"
#   • gh CLI authenticated: gh auth login
#   • Sparkle EdDSA private key in the login keychain (shared with Claude Meter)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Bopop"
TEAM_ID="${TEAM_ID:-4L4SS26L9J}"
KEYCHAIN_PROFILE="notarytool"
GITHUB_REPO="jewei/bopop"
MIN_MACOS="15.0"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"

# ── Version ───────────────────────────────────────────────────────────────────
# Marketing version is manual in Support/Info.plist; build number is the git
# commit count — monotonic by construction (the release commit guarantees it
# grows between releases). Sparkle compares CFBundleVersion → sparkle:version.

PLIST_SRC="$PROJECT_DIR/Support/Info.plist"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")}"
BUILD="${2:-$(git -C "$PROJECT_DIR" rev-list --count HEAD)}"

DMG_NAME="$APP_NAME-$VERSION.dmg"
TAG="v$VERSION"

if git -C "$PROJECT_DIR" rev-parse "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "error: tag $TAG already exists — bump CFBundleShortVersionString first." >&2
    exit 1
fi

echo "▶ Releasing $APP_NAME $VERSION (build $BUILD)"

# ── Build & assemble (mirrors `make app`, but stamps the build number and
#    signs components individually with Developer ID + hardened runtime) ──────

APP_PATH="$PROJECT_DIR/dist/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/dist/$DMG_NAME"
NOTARIZE_ZIP="$PROJECT_DIR/dist/$APP_NAME-notarize.zip"
SPARKLE_ARTIFACTS="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle"
SPARKLE_FMWK="$SPARKLE_ARTIFACTS/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SIGN_UPDATE="$SPARKLE_ARTIFACTS/bin/sign_update"

echo "▶ Building…"
swift build -c release --package-path "$PROJECT_DIR"

if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "error: $SIGN_UPDATE not found — did swift build resolve the Sparkle package?" >&2
    exit 1
fi

rm -rf "$APP_PATH" "$DMG_PATH" "$NOTARIZE_ZIP"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Frameworks"
cp "$PROJECT_DIR/.build/release/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$PLIST_SRC" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "$SPARKLE_FMWK" "$APP_PATH/Contents/Frameworks/"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_PATH/Contents/Info.plist"

# ── Sign (inside-out: Sparkle's nested executables, the framework, the app) ───

echo "▶ Signing with Developer ID…"
FMWK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/Autoupdate"
codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/Updater.app"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$FMWK"
codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"

# ── Notarize & staple ─────────────────────────────────────────────────────────

echo "▶ Submitting to Apple notary service…"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"
xcrun notarytool submit "$NOTARIZE_ZIP" \
    --team-id "$TEAM_ID" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait

echo "▶ Stapling…"
xcrun stapler staple "$APP_PATH"

# ── DMG ───────────────────────────────────────────────────────────────────────

echo "▶ Creating DMG…"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"

# ── Sign for Sparkle ──────────────────────────────────────────────────────────

echo "▶ Signing DMG for Sparkle…"
SIGN_OUTPUT=$("$SIGN_UPDATE" "$DMG_PATH")
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGN_OUTPUT"    | grep -o 'length="[^"]*"'              | cut -d'"' -f2)

echo "   edSignature: $SIGNATURE"
echo "   length:      $LENGTH"

# ── Rewrite appcast.xml ───────────────────────────────────────────────────────

echo "▶ Updating appcast.xml…"
PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$DMG_NAME"

cat > "$PROJECT_DIR/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Bopop</title>
        <link>https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml</link>
        <description>Bopop release feed</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://github.com/$GITHUB_REPO/releases/tag/$TAG</sparkle:releaseNotesLink>
            <enclosure
                url="$DOWNLOAD_URL"
                sparkle:edSignature="$SIGNATURE"
                length="$LENGTH"
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
XML

# Fail before changing git state or publishing anything if the signed
# artifacts, mounted DMG, or appcast metadata do not agree.
"$SCRIPT_DIR/validate-release.sh" "$APP_PATH" "$DMG_PATH" "$PROJECT_DIR/appcast.xml"

# ── Commit, push, release ─────────────────────────────────────────────────────
# Push BEFORE creating the release: GitHub's target_commitish must already
# exist on the remote. The appcast download URL points at the release asset
# (uploaded below), so publishing the commit first never exposes a dangling
# appcast — clients fetch the new feed only after the asset is live or 404
# harmlessly for the moment in between.

echo "▶ Committing appcast.xml + version…"
git -C "$PROJECT_DIR" add appcast.xml Support/Info.plist
git -C "$PROJECT_DIR" commit -m "Release $TAG"
RELEASE_COMMIT="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

echo "▶ Pushing to origin…"
git -C "$PROJECT_DIR" push

echo "▶ Creating GitHub release ${TAG}…"
gh release create "$TAG" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --target "$RELEASE_COMMIT" \
    --title "$APP_NAME $VERSION" \
    --generate-notes

echo ""
echo "✓ Released $APP_NAME $VERSION"
echo "  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
