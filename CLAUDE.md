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
- **Gotchas:** `docs/gotchas.md` — platform behaviour that reads as a bug, or
  as pointless code, until you know it. Several are cited by number from the
  source. Read it before "simplifying" anything that looks redundant.

## Architecture

Queries flow one way:

```
PaletteState → QueryEngine → Providers (concurrent) → Ranker
     ↑                                                   │
     └──────────── PaletteRenderPlan ────────────────────┘
                          ↓
              PaletteController (adapter) → ActionRunner
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

### The palette

`PaletteState` owns everything about the palette that is Foundation-
representable: query text, sticky and effective mode, results, hero,
selection, restoration id, and the key used to skip an unchanged redraw.
Every command returns a `PaletteRenderPlan`; `PaletteController` draws the
plan and runs its effects, and never writes any of that state itself.

- **`PaletteState` is the only writer.** The controller is an adapter. If you
  find yourself adding a mutable `results`/`selectedIndex`/`stickyMode` to the
  controller, the change belongs in the module instead.
- **Parse exactly once.** `PaletteState` parses; `QueryEngine.update(query:)`
  takes an already-parsed query and reports it back on `Update.query`, and an
  update whose query doesn't match the current one is ignored. Re-parsing
  `queryField.stringValue` on receipt is a second clock — it is how a mode
  prefix ended up drawn against the previous mode's rows.
- **Two pure modules hang off it.** `PaletteGeometry` owns the panel-height
  rules (the design tokens stay in `PaletteMetrics`, injected); `route(_:
  overlays:)` in `PaletteKeyRouting` owns what a key means. Both are pure, so
  both are table-tested. AppKit decoding — `NSEvent` chords, `NSResponder`
  selectors — stays in the adapter.
- **Resist one-caller helpers.** Six of them accumulated here, each extracted
  to make a test possible rather than to hide a decision from a second caller.
  The arithmetic ended up tested and the composition — where every bug lived —
  did not. They are gone; don't grow them back.

## Critical invariants

Don't break these without meaning to.

- **`sortHint` is the provider's ordering intent** and breaks score ties ahead
  of the alphabetical fallback, for *every* query. Gating it on an empty query
  scattered pinned clipboard rows through filtered history.
- **`QueryParser` trims in every mode**, sticky included. `Ranker` folds case
  and diacritics but never trims, so an untrimmed term makes one trailing
  space tier-mismatch every candidate and blank the list mid-word.
- **Selection is `PaletteFocus` — `.none`, `.hero`, or `.row(Int)`.** Not an
  index with a sentinel: `.row(4)` over an empty list is not constructible,
  which is what finally settled two layers that disagreed about what an empty
  grid selects. `PaletteState.apply(_:)` resets focus on each update unless a
  stay-open action (pin, unpin, hide) named a row to restore — that restoration
  survives interim updates and is spent on the final one, which is what keeps
  ⏎ pointed at the row the action just touched.
- **A draw must never re-enter a draw.** `PaletteController.commit` holds
  `isApplyingPlan` for the *whole* draw, not just the selection call.
  `reloadData()` changes the table's selection and fires
  `tableViewSelectionDidChange` synchronously, so a narrower guard lets the
  delegate mistake our own reload for a user click and re-enter against
  half-updated views. That shipped once: the re-entrant pass reached the
  collection view while it still held the previous mode's items, AppKit wedged,
  and the hung job killed the MainActor executor — every later engine update
  was silently never delivered. No test catches this; see Known gaps.
- **Overlay panels resign key when another Bopop overlay takes it.**
  `FocusLossCheck.isForeign(successor:ownPanel:)` decides, and `runDeferred`
  waits one runloop turn so the successor is known — the only way to tell "own
  overlay took key" from "user switched app". Dismissing an overlay must
  explicitly re-key the palette.
- **The actions panel never becomes key.** It's a non-activating child panel;
  the query field keeps focus and `PaletteController` routes keys to it. That
  is why the caret never needs freezing — and it is load-bearing for
  `FocusLossCheck`, whose allowlist does *not* include the plain `NSPanel` the
  actions panel is built from. If it ever became key it would read as genuine
  focus loss and tear the palette down. A test pins both halves.
- **A key the palette declines must report unhandled.** `route` returns
  `.passThrough` rather than a bare `false`, and the adapter must propagate it:
  that is what lets ←/→ move the caret and ⌘C copy selected text out of the
  query field. Reporting it handled silently swallows the keystroke.
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

## Known gaps

Written down so they aren't rediscovered the hard way.

- **AppKit re-entrancy is not covered by any test.** `PaletteController` can be
  constructed and driven now (`Tests/BopopTests/PaletteControllerTests.swift`),
  which covers wiring — typing reaches the engine, results reach the table, the
  grid and table swap, focus lands where the plan says. It does *not* cover
  delegate re-entrancy: an off-screen `NSTableView` doesn't fire its selection
  delegate from `reloadData()`, so reverting the `isApplyingPlan` guard leaves
  the suite green. A visible panel and changing row counts don't reproduce it
  either. Closing this needs a UI test host the project doesn't have, so until
  then **a change to the palette's AppKit half needs a manual smoke test**, and
  `make run` is the way to do it.
- **`show()` needs a screen.** It returns early when no `NSScreen` owns the
  palette, so anything asserting `panel.isVisible` passes locally and fails on
  CI. Assert on an observable that doesn't need a window — see
  `hideCountForTesting`.

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
