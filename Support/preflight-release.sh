#!/usr/bin/env bash
# Repository preconditions for cutting a release. Runs before anything is
# built, signed, or submitted, so a doomed run costs nothing.
# usage: preflight-release.sh <version>
#
# Extracted from release.sh so it can be run — and trusted — on its own:
# every check here is read-only, which is what makes it safe to exercise
# without publishing.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

VERSION="$1"
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

# ── Up to date with origin ────────────────────────────────────────────────────

if ! git_in fetch --quiet origin "$RELEASE_BRANCH" 2>/dev/null; then
    echo "error: could not fetch origin/$RELEASE_BRANCH." >&2
    exit 1
fi
BEHIND="$(git_in rev-list --count "HEAD..origin/$RELEASE_BRANCH")"
if [[ "$BEHIND" != "0" ]]; then
    echo "error: $BRANCH is $BEHIND commit(s) behind origin/$RELEASE_BRANCH — pull first." >&2
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
