#!/usr/bin/env bash
# Repository preconditions for cutting a release. Runs before anything is
# built, signed, or submitted, so a doomed run costs nothing.
# usage: preflight-release.sh <version> [github-owner/repository]
#
# Extracted from release.sh so it can be run — and trusted — on its own:
# every check here is read-only, which is what makes it safe to exercise
# without publishing.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <version> [github-owner/repository]" >&2
    exit 2
fi

VERSION="$1"
GITHUB_REPO="${2:-jewei/bopop}"
TAG="v$VERSION"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"

git_in() {
    git -C "$PROJECT_DIR" "$@"
}

echo "▶ Preflight for $TAG"

# ── Version shape ─────────────────────────────────────────────────────────────
# Catches an inverted argument order (`release.sh 138 0.1.3`) before it becomes
# a tag, a DMG name, and an appcast entry.

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version '$VERSION' is not MAJOR.MINOR.PATCH." >&2
    exit 1
fi

# ── Branch ────────────────────────────────────────────────────────────────────
# The release commit is pushed to whatever branch is checked out, and the
# GitHub release targets that commit — cutting from a feature branch would
# publish an unreviewed tree.

BRANCH="$(git_in rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "$RELEASE_BRANCH" ]]; then
    echo "error: releases are cut from $RELEASE_BRANCH; currently on $BRANCH." >&2
    exit 1
fi

# ── Clean tree ────────────────────────────────────────────────────────────────
# The release commit stages only appcast.xml and Info.plist, so uncommitted
# work would silently ship in the BUILD while staying absent from the commit
# that claims to describe it.

if [[ -n "$(git_in status --porcelain)" ]]; then
    echo "error: working tree is dirty — commit or stash first:" >&2
    git_in status --short >&2
    exit 1
fi

# ── Exact remote commit ───────────────────────────────────────────────────────

if ! git_in fetch --quiet origin "$RELEASE_BRANCH" 2>/dev/null; then
    echo "error: could not fetch origin/$RELEASE_BRANCH." >&2
    exit 1
fi
LOCAL_SHA="$(git_in rev-parse HEAD)"
REMOTE_SHA="$(git_in rev-parse "origin/$RELEASE_BRANCH")"
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
    echo "error: HEAD $LOCAL_SHA is not exactly origin/$RELEASE_BRANCH $REMOTE_SHA." >&2
    echo "       Pull, push, or reset the branch before releasing." >&2
    exit 1
fi

# ── Publication prerequisites and exact-SHA CI ────────────────────────────────

for command in gh xcrun codesign hdiutil xmllint security; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "error: required release tool is missing: $command" >&2
        exit 1
    fi
done
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    echo "error: gh is not authenticated for github.com." >&2
    exit 1
fi
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-notarytool}"
TEAM_ID="${TEAM_ID:-4L4SS26L9J}"
if ! security find-identity -v -p codesigning | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "error: no codesigning identity matches '$SIGN_IDENTITY'." >&2
    exit 1
fi
if ! xcrun notarytool history \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --team-id "$TEAM_ID" \
    --output-format json >/dev/null 2>&1; then
    echo "error: notarytool profile '$KEYCHAIN_PROFILE' is unavailable or invalid." >&2
    exit 1
fi
REPO_PUSH_PERMISSION="$(gh api "repos/$GITHUB_REPO" --jq '.permissions.push // false' 2>/dev/null || true)"
if [[ -z "$REPO_PUSH_PERMISSION" ]]; then
    echo "error: authenticated gh account cannot read $GITHUB_REPO." >&2
    exit 1
fi
if [[ "$REPO_PUSH_PERMISSION" != "true" ]]; then
    echo "error: authenticated gh account cannot publish to $GITHUB_REPO." >&2
    exit 1
fi

# The release must describe the exact reviewed commit, not merely a branch with
# some successful historical run. The workflow-run query pins the repository's
# CI workflow to this exact head SHA.
CI_CONCLUSION="$(gh run list \
    --repo "$GITHUB_REPO" \
    --workflow CI \
    --commit "$LOCAL_SHA" \
    --limit 1 \
    --json conclusion \
    --jq '.[0].conclusion // "missing"')"
if [[ "$CI_CONCLUSION" != "success" ]]; then
    echo "error: CI for exact commit $LOCAL_SHA is '$CI_CONCLUSION', not successful." >&2
    exit 1
fi

# ── Tag availability ──────────────────────────────────────────────────────────
# `ls-remote --exit-code` returns 0 when refs match and 2 when none do;
# anything else is a real failure (offline, auth, bad remote). Treating every
# non-zero status as "tag is free" — as this check used to — meant a network
# blip read as permission to proceed.

LS_STATUS=0
git_in ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 || LS_STATUS=$?
case "$LS_STATUS" in
    0)
        echo "error: tag $TAG already exists on origin — pick a new version." >&2
        exit 1
        ;;
    2)
        : # No such tag: the one status that may proceed.
        ;;
    *)
        echo "error: could not check origin for $TAG (git ls-remote exit $LS_STATUS)." >&2
        exit 1
        ;;
esac

echo "✓ Preflight passed: $BRANCH clean and current, $TAG available"
