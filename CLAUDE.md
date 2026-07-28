# Bopop

Keyboard-first macOS launcher. Runs as an accessory (`LSUIElement`) — no Dock
icon, no menu-bar item; Settings/Scripts/Quit come from the palette footer.
SwiftPM, Swift 6 language mode, macOS 15+, Xcode 26.

- **Build:** `make test` (full suite), `make app`, `make run`, `make open`.
  Release: `Support/release.sh <version>` — see [Release](#release).
- **Targets:** `BopopKit` (pure logic) and `Bopop` (AppKit + SwiftUI app).
  Tests: `Tests/BopopKitTests`, `Tests/BopopTests`.
- **CI:** `.github/workflows/ci.yml` builds and tests every push to `main`
  and every PR.

## Architecture

Queries flow one way:

```
QueryParser → QueryEngine → Providers (concurrent) → Ranker → PaletteController → ActionRunner
```

- **`BopopKit` is Foundation-only.** No `import AppKit` or `SwiftUI` — the
  SwiftPM target boundary enforces it, which is why parsing, ranking, and the
  providers are testable without a UI. Anything needing AppKit is injected as
  a closure from `AppDelegate` (running apps, hidden ids, settings lookups).
- **`AppDelegate.init()` is the single wiring point.** Constructor injection,
  no singletons. New long-lived state is constructed and passed there.
- **Providers are `nonisolated`.** They run concurrently in a task group, so
  they must never touch MainActor state without an explicit
  `await MainActor.run { ... }` snapshot. `assumeIsolated` is banned in a
  provider body.

## Critical invariants

Don't break these without meaning to.

- **`sortHint` is the provider's ordering intent** and breaks score ties ahead
  of the alphabetical fallback, for *every* query. Gating it on an empty query
  scattered pinned clipboard rows through filtered history.
- **`QueryParser` trims in every mode**, sticky included. `Ranker` folds case
  and diacritics but never trims, so an untrimmed term makes one trailing
  space tier-mismatch every candidate and blank the list mid-word.
- **Selection is an index into `results`, with `-1` meaning the hero card.**
  `apply(_:)` resets it to 0 on each update unless `selectionToRestore` names
  a row — that's what keeps ⏎ pointed at the row a stay-open action (pin,
  unpin, hide) just acted on.
- **Overlay panels resign key when another Bopop overlay takes it.**
  `FocusLossCheck` defers one runloop turn and inspects the successor window,
  which is the only way to tell "own overlay took key" from "user switched
  app". Dismissing an overlay must explicitly re-key the palette.
- **The actions panel never becomes key.** It's a non-activating child panel;
  the query field keeps focus and `PaletteController` routes keys to it. That
  is why the caret never needs freezing.
- **Storage is a `{version, payload}` envelope**, atomic, `0600`. A decode
  failure quarantines the file; `loadElements` decodes arrays element-wise so
  one bad record doesn't cost the user the rest. Additive fields must use
  `decodeIfPresent` — bumping the version quarantines existing data.
- **Clipboard secrecy markers live in one set.** `ClipboardCapturePolicy.sensitiveTypes`
  is the only place that decides what is never recorded.
- **Pins are exempt from the history limit but not from everything.** They
  survive Clear and the trim, have their own cap, and are never scrubbed by
  the upstream-clear heuristic — that heuristic can't identify who cleared the
  pasteboard, so it must not delete something explicitly kept.
- **Networked features are consent-gated, and the safe state is the default.**
  Currency is the only feature that leaves the machine. `CurrencyProvider`'s
  `isEnabled` defaults to `{ false }`, so forgetting to wire it disables the
  fetch rather than enabling it, and consent is re-checked on *both* sides of
  the network `await` because it can be withdrawn mid-flight. Turning it off
  deletes the cached rates.
- **No Accessibility permission, ever.** Bopop does not paste into other apps
  and does not tap events. Scripts run via `Process` with absolute paths and
  no shell; `ActionRunner.allowedURL` allowlists `http`/`https`/`dict`.
- **Destructive commands confirm.** Either macOS does it (the loginwindow
  events) or `SystemCommand.confirmation` does. The `…` title suffix marks
  exactly the commands that confirm — a test pins that both ways.

## Dev channel

`make run` / `make open` stamp a `.dev` bundle identifier and product name.
UserDefaults, the login item, Sparkle's state and — via
`Storage.directoryName(forBundleIdentifier:)` — Application Support are all
keyed by bundle identifier, so a build from source can't read or clobber an
installed Bopop's data, and `AppUpdater` won't offer to replace your working
build with the last shipped DMG. `make app` and `Support/release.sh` keep the
release identity untouched.

## Release

`Support/release.sh <version>` builds, signs (Developer ID), notarizes,
staples, makes a DMG, signs it for Sparkle, rewrites `appcast.xml`, commits,
pushes, and creates the GitHub release. Two guards bracket it:

- `Support/preflight-release.sh` — branch, clean tree, up to date with origin,
  tag available, version shape. Read-only, so it's safe to run on its own.
- `Support/validate-release.sh` — signature, notarization, DMG integrity, and
  appcast metadata against the real artifacts, before any git state changes.

Always pass the version explicitly. It is written back to `Support/Info.plist`
as part of the release commit.

## Generated data

`Sources/BopopKit/Resources/emoji.json` is generated, not hand-edited:

```sh
swift Support/generate-emoji.swift > Sources/BopopKit/Resources/emoji.json
```

It fetches from the network and the output is committed.
