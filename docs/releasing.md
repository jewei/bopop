# Releasing

`Support/release.sh <version>` builds, signs with Developer ID, notarizes,
staples, makes a DMG, signs it for Sparkle, rewrites `appcast.xml`, validates the
artifacts, commits, pushes, and creates the GitHub release.

The preflight enforces repository, CI, credential, and publication prerequisites
before the expensive build starts. `release.sh` also verifies the commit- and
version-bound manual QA result sheet before building.

## Version policy

- Patch: backward-compatible bug and security fixes.
- Minor: new features or intentional user-facing behavior changes.
- Major: incompatible behavior or data/API contracts once the project reaches
  a stable major release.

During `0.x`, use the same patch/minor distinction; do not claim that a patch
means “nothing moved.” Pass the version explicitly. The release script writes it
back to `Support/Info.plist` in the release commit.

## Required gates

### 1. Reviewed, remote source commit

Preflight requires the exact reviewed `origin/main` commit—neither behind nor
locally ahead—and a successful `CI` workflow run for that SHA. To inspect the
same condition before starting:

```sh
git fetch origin main
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
```

`Support/preflight-release.sh <version>` performs this check again and fails if
the matching workflow run is missing or unsuccessful.

### 2. Manual behavior QA

Run the AppKit, privacy, permission, hotkey, and screen-geometry checklist on
the exact release candidate:

```sh
Support/qa-release.sh --version <version>
Support/qa-release.sh --version <version> --check
```

`--check` succeeds only when every expected verdict is present, no failure or
unreviewed skip remains, and the result sheet names the current commit and
version. A reviewed skip must have a reason and release-owner sign-off. Record
the final ready result and any reviewed skips in the release PR or release
record; the detailed local sheet stays ignored.

### 3. Credentials and publication access

Preflight verifies the required tools, GitHub authentication and repository
access, the Developer ID identity, and the notarytool profile. To diagnose a
failure directly:

```sh
security find-identity -v -p codesigning
xcrun notarytool history --keychain-profile notarytool
gh auth status
gh repo view jewei/bopop
```

Also confirm the Sparkle EdDSA private key is available to `sign_update`; its
executable and output are checked during the build.

## Automated guards

- `Support/preflight-release.sh <version>` checks version shape, branch, clean
  tree, exact equality with `origin/main`, exact-SHA CI, required tools,
  publication credentials, and remote tag availability. It is read-only.
- `Support/validate-release.sh` checks code signatures, notarization, DMG
  integrity, the mounted application, and appcast metadata before Git changes.
- `Support/qa-release.sh --version <version> --check` checks behavior evidence.
  It is read-only with respect to tracked source and exits nonzero unless the
  sheet is ready.

## Cut and recovery

```sh
Support/release.sh <version>
```

The script builds an isolated release commit and first pushes it to
`release-staging/v<version>`. It publishes and verifies the GitHub release asset
before fast-forwarding `main`, so a publication failure does not expose a
dangling appcast.

If GitHub release creation or asset verification fails, `main` is unchanged.
Preserve the built DMG and staging ref, repair the cause, and complete or remove
the partial GitHub release against the staging commit. Do not invent a second
version.

```sh
release_commit="$(git ls-remote origin \
  "refs/heads/release-staging/v<version>" | cut -f1)"
gh release create "v<version>" "dist/Bopop-<version>.dmg" \
  --repo jewei/bopop \
  --target "$release_commit" \
  --title "Bopop <version>" \
  --generate-notes
```

If the release and asset are live but the final main push was interrupted, use
the exact recovery command printed by the script. It is protected by
`--force-with-lease` against concurrent changes. Do not weaken that lease. After
main advances, fast-forward the local branch and delete the staging ref.

Confirm the asset URL in `appcast.xml` downloads successfully. If a defect is
found after main exposes the feed, use a normal reviewed fix or revert; never
delete or rewrite shared main history.
