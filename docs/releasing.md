# Releasing

`Support/release.sh <version>` does the whole cut: builds, signs (Developer
ID), notarizes, staples, makes a DMG, signs it for Sparkle, rewrites
`appcast.xml`, commits, pushes, and creates the GitHub release. Rewriting the
appcast is what offers the update to every existing install, so the push is the
point of no return.

Pass the version explicitly. It is written back to `Support/Info.plist` as part
of the release commit.

## Guards

Two bracket the run, and both are worth knowing separately:

- `Support/preflight-release.sh <version>` — branch, clean tree, up to date
  with origin, tag available, version shape. Every check is read-only, which is
  what makes it safe to run on its own before committing to anything.
- `Support/validate-release.sh` — signature, notarization, DMG integrity and
  appcast metadata, checked against the real artifacts before any git state
  changes.

## Prerequisites

All from the login keychain: a Developer ID Application certificate, notarytool
credentials stored under the `notarytool` profile
(`xcrun notarytool store-credentials`), and the Sparkle EdDSA private key.

## Versioning

Bump the minor for anything a user can feel, including changed behaviour — a
patch bump reads as "nothing moved". `0.3.0` carried a rendering fix and new
grid-arrow semantics; both were felt, neither was a new feature.
