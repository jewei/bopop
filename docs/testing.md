# Testing

## Automated suite

```sh
make test
```

`BopopKitTests` cover parsing, ranking, providers, storage, and palette state.
`BopopTests` cover application-layer wiring and the seams AppKit permits. CI
runs `swift build --build-tests` and `swift test` on pushes to `main` and pull
requests.

Optional live Spotlight tests run with:

```sh
BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live
```

The same suite must also pass under production optimization before release:

```sh
swift test -c release
```

This catches isolation and optimization-only compilation failures that the
debug configuration cannot expose.

## What green tests do not prove

Mutation checking proves that a test notices a code change. It does not prove
the expected behavior is correct. Tests created from existing behavior need an
independent product or platform reason for the expectation. The former
`noSuccessorIsAFocusLoss` test was mutation-sensitive and still pinned a bug.

The palette's AppKit half has no faithful UI test host. An off-screen
`NSTableView` does not reproduce the synchronous selection callback that caused
the re-entrant draw hang; reverting the full-draw guard leaves controller tests
green. Real window focus handoffs, system panels, permissions, global-hotkey
contention, and screen geometry also require a human session.

Carbon's registration result diagnoses Bopop's local handler or registration
failure; it does not establish exclusivity across processes. Unit tests inject
those local outcomes and cover their Settings presentation. The manual
checklist verifies the separately detectable Spotlight conflict and ensures the
UI does not revive an unsupported generic “another app owns this” claim.

## Mandatory manual release QA

Run or resume the commit-bound checklist. Pass the intended release version
explicitly when it differs from `Support/Info.plist`:

```sh
Support/qa-release.sh --version <version>
```

It records local verdicts in `.qa-results` by default. A verdict is one of:

- `pass`;
- `FAIL: reason`;
- `skip-reviewed: reason`;
- `skip-unreviewed: reason`.

A release is ready only when every expected check is present, no failure or
unreviewed skip remains, and the sheet names the exact commit and version being
released:

```sh
Support/qa-release.sh --version <version> --check
```

The check exits nonzero and writes `QA_RELEASE_STATUS=blocked` otherwise.
Detailed sheets stay ignored because they may contain machine-specific notes;
the release PR or release record should state the exact commit, who reviewed
skips, and the final `ready` result.
