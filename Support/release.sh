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
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-notarytool}"
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

# Branch, clean tree, exact remote SHA, successful CI for that SHA, publication
# credentials, and tag availability — all read-only, all before anything is
# built or submitted. See Support/preflight-release.sh.
"$SCRIPT_DIR/preflight-release.sh" "$VERSION" "$GITHUB_REPO"
# Manual behavior checks are commit- and version-bound. A release cannot rely
# on a stale or partially reviewed worksheet.
"$SCRIPT_DIR/qa-release.sh" --version "$VERSION" --check
BASE_COMMIT="$(git -C "$PROJECT_DIR" rev-parse HEAD)"

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
PRODUCTS_DIR="$(swift build \
    -c release \
    --arch arm64 \
    --arch x86_64 \
    --package-path "$PROJECT_DIR" \
    --show-bin-path)"

if [[ ! -x "$SIGN_UPDATE" ]]; then
    echo "error: $SIGN_UPDATE not found — did swift build resolve the Sparkle package?" >&2
    exit 1
fi

# Exercise the Sparkle key before signing or notarizing the real artifact. The
# binary being present proves only that the dependency resolved; sign_update
# still fails later if the EdDSA private key is missing or inaccessible.
SIGNING_PROBE="$(mktemp)"
printf 'Bopop release signing preflight\n' > "$SIGNING_PROBE"
if ! "$SIGN_UPDATE" "$SIGNING_PROBE" >/dev/null 2>&1; then
    rm -f "$SIGNING_PROBE"
    echo "error: Sparkle sign_update cannot access a signing key." >&2
    exit 1
fi
rm -f "$SIGNING_PROBE"

rm -rf "$DMG_PATH" "$NOTARIZE_ZIP"
"$SCRIPT_DIR/assemble-app.sh" "$PRODUCTS_DIR" "$PLIST_SRC" "$APP_PATH"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP_PATH/Contents/Info.plist"

# ── Sign (inside-out: Sparkle's nested executables, the framework, the app) ───

echo "▶ Signing with Developer ID…"
FMWK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/XPCServices/Downloader.xpc"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/XPCServices/Installer.xpc"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/Autoupdate"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" \
    "$FMWK/Versions/B/Updater.app"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FMWK"
codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_PATH"

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
SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2 || true)
LENGTH=$(echo "$SIGN_OUTPUT"    | grep -o 'length="[^"]*"'              | cut -d'"' -f2 || true)

if [[ -z "$SIGNATURE" || -z "$LENGTH" ]]; then
    echo "error: could not parse sign_update output:" >&2
    echo "$SIGN_OUTPUT" >&2
    exit 1
fi

echo "   edSignature: $SIGNATURE"
echo "   length:      $LENGTH"

# ── Rewrite appcast.xml ───────────────────────────────────────────────────────

echo "▶ Preparing appcast.xml…"
PUBDATE=$(date -u '+%a, %d %b %Y %H:%M:%S +0000')
DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$DMG_NAME"
STAGED_APPCAST="$(mktemp)"
STAGED_PLIST="$(mktemp)"
TEMP_INDEX="$(mktemp)"
rm -f "$TEMP_INDEX"
cleanup_staged_files() {
    rm -f "$STAGED_APPCAST" "$STAGED_PLIST" "$TEMP_INDEX"
}
trap cleanup_staged_files EXIT

cat > "$STAGED_APPCAST" <<XML
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
"$SCRIPT_DIR/validate-release.sh" "$APP_PATH" "$DMG_PATH" "$STAGED_APPCAST"

# ── Stage, publish asset, then expose appcast ─────────────────────────────────
# The release commit first goes to a temporary remote ref. That gives GitHub a
# reachable target without changing main (and therefore without exposing the
# new appcast). The release asset is published next; only then is main
# fast-forwarded. A failure before that final push leaves the live feed intact.

# Write the shipped version into a staged plist, so the repository tracks reality
# rather than drifting behind (it sat at 0.1.1 through the 0.1.2 and 0.1.3
# releases, which made the no-argument default useless — it would resolve to
# an already-tagged version and fail preflight). Deliberately last: everything
# above is read-only with respect to the repo, and the release commit below is
# built with git plumbing without moving the local branch. A failed publication
# therefore leaves the checkout exactly as preflight found it.
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_SRC")"
cp "$PLIST_SRC" "$STAGED_PLIST"
if [[ "$PLIST_VERSION" != "$VERSION" ]]; then
    # Braces are load-bearing: bash 3.2 on macOS takes the bytes of the
    # following "…" as part of the variable name, so `$VERSION…` looks up
    # VERSION… and `set -u` kills the release after notarization.
    echo "▶ Updating Support/Info.plist $PLIST_VERSION → ${VERSION}…"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$STAGED_PLIST"
fi

echo "▶ Creating isolated release commit…"
APPCAST_BLOB="$(git -C "$PROJECT_DIR" hash-object -w "$STAGED_APPCAST")"
PLIST_BLOB="$(git -C "$PROJECT_DIR" hash-object -w "$STAGED_PLIST")"
GIT_INDEX_FILE="$TEMP_INDEX" git -C "$PROJECT_DIR" read-tree "$BASE_COMMIT"
GIT_INDEX_FILE="$TEMP_INDEX" git -C "$PROJECT_DIR" update-index \
    --cacheinfo "100644,$APPCAST_BLOB,appcast.xml"
GIT_INDEX_FILE="$TEMP_INDEX" git -C "$PROJECT_DIR" update-index \
    --cacheinfo "100644,$PLIST_BLOB,Support/Info.plist"
RELEASE_TREE="$(GIT_INDEX_FILE="$TEMP_INDEX" git -C "$PROJECT_DIR" write-tree)"
RELEASE_COMMIT="$(printf 'Release %s\n' "$TAG" | \
    git -C "$PROJECT_DIR" commit-tree "$RELEASE_TREE" -p "$BASE_COMMIT")"
STAGING_REF="refs/heads/release-staging/$TAG"

echo "▶ Staging release commit without changing main…"
git -C "$PROJECT_DIR" push origin "$RELEASE_COMMIT:$STAGING_REF"

echo "▶ Publishing GitHub release ${TAG} and asset…"
gh release create "$TAG" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --target "$RELEASE_COMMIT" \
    --title "$APP_NAME $VERSION" \
    --generate-notes

# Verify the published URL before main starts advertising it. `gh release view`
# proves publication state; the asset lookup proves the exact expected name was
# attached rather than relying on gh's successful exit alone.
PUBLISHED_ASSET="$(gh release view "$TAG" \
    --repo "$GITHUB_REPO" \
    --json assets \
    --jq ".assets[] | select(.name == \"$DMG_NAME\") | .name")"
if [[ "$PUBLISHED_ASSET" != "$DMG_NAME" ]]; then
    echo "error: published release is missing $DMG_NAME; main was not changed." >&2
    exit 1
fi

echo "▶ Fast-forwarding main after the release asset is live…"
RECOVERY_COMMAND="git push --force-with-lease=refs/heads/main:$BASE_COMMIT origin $RELEASE_COMMIT:refs/heads/main"
echo "   If this final push is interrupted, recover with: $RECOVERY_COMMAND"
git -C "$PROJECT_DIR" push --force-with-lease="refs/heads/main:$BASE_COMMIT" \
    origin "$RELEASE_COMMIT:refs/heads/main"
git -C "$PROJECT_DIR" merge --ff-only "$RELEASE_COMMIT"
git -C "$PROJECT_DIR" push origin --delete "release-staging/$TAG" || true

echo ""
echo "✓ Released $APP_NAME $VERSION"
echo "  https://github.com/$GITHUB_REPO/releases/tag/$TAG"
