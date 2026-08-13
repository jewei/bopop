# Bopop

Keyboard-first macOS launcher. Runs as an accessory (`LSUIElement`) — no Dock
icon, no menu-bar item; Settings/Scripts/Quit come from the palette footer.
SwiftPM, Swift 6 language mode, macOS 15+, Xcode 26.

- **Build:** `make test` (full suite), `make app`, `make run`, `make open`.
  `make run` stamps a `.dev` bundle id, and defaults, login item, Sparkle state
  and Application Support are all keyed by bundle id — so a build from source
  can't read or clobber an installed Bopop.
- **Targets:** `BopopKit` (pure logic) and `Bopop` (AppKit + SwiftUI app).
  Tests: `Tests/BopopKitTests`, `Tests/BopopTests`.
- **[`docs/gotchas.md`](docs/gotchas.md)** — platform behaviour that reads as a
  bug, or as pointless code, until you know it. Several entries are cited by
  number from the source. Read it before simplifying anything that looks
  redundant, and before changing the palette's AppKit half.
- **[`docs/README.md`](docs/README.md)** — the documentation map. In particular,
  read `docs/testing.md` before trusting a green suite and `docs/releasing.md`
  before cutting a release.

## Architecture

Queries flow one way, and the answer comes back as a plan to draw:

```
PaletteState → QueryEngine → Providers (concurrent) → Ranker
     ↑                                                   │
     └──────── PaletteRenderPlan ← ──────────────────────┘
                     ↓
         PaletteController (adapter) → ActionRunner
```

- **`BopopKit` has no AppKit or SwiftUI.** It also uses non-UI Apple modules
  such as `os` and UniformTypeIdentifiers, so “Foundation-only” is not literal.
  SwiftPM enforces the dependency direction; the UI-import ban is a review
  convention. Anything needing AppKit arrives through the app adapter.
- **`AppDelegate.init()` is the single wiring point.** Constructor injection,
  no singletons. New long-lived state is constructed and passed there.
- **Providers are `Sendable` and run concurrently** outside the main actor.
  They reach MainActor state only through an explicit awaited snapshot. Use
  that snapshot rather than `assumeIsolated`, which is unsound here and rejected
  in review.

### The palette

`PaletteState` owns everything about the palette that is Foundation-
representable: query text, sticky and effective mode, results, hero, selection,
restoration id, and the key used to skip an unchanged redraw. Every command
returns a `PaletteRenderPlan`; `PaletteController` draws the plan and runs its
effects.

- **`PaletteState` is the only writer, the controller is an adapter.** State
  that belongs to the palette goes in the module; the controller holds AppKit.
- **Parse exactly once.** `PaletteState` parses, `QueryEngine.update(query:)`
  takes the parsed query and reports it back on `Update.query`, and an update
  whose query doesn't match the current one is ignored. Re-parsing on receipt
  is a second clock, and it drew a mode prefix against the previous mode's rows.
- **Pure modules beside it, table-tested:** `PaletteGeometry` (panel-height
  rules; the design tokens stay in `PaletteMetrics` and are injected) and
  `PaletteKeyRouting.route(_:overlays:)` (what a key means). AppKit decoding —
  `NSEvent` chords, `NSResponder` selectors — stays in the adapter.
- **One module, many callers.** Six single-caller helpers accumulated here,
  each extracted to make a test possible rather than to hide a decision. The
  arithmetic ended up tested and the composition, where every bug lived, did
  not. Extract when a second caller exists.

## Critical invariants

- **`sortHint` is the provider's ordering intent** and breaks score ties ahead
  of the alphabetical fallback, for *every* query. Gating it on an empty query
  scattered pinned clipboard rows through filtered history.
- **`QueryParser` trims in every mode**, sticky included. `Ranker` folds case
  and diacritics but never trims, so one trailing space tier-mismatches every
  candidate and blanks the list mid-word.
- **Selection is `PaletteFocus`** — `.none`, `.hero`, `.row(Int)`. Not an index
  with a sentinel, so `.row(4)` over an empty list is unconstructible.
  `apply(_:)` resets focus each update unless a stay-open action (pin, unpin,
  hide) named a row to restore; that restoration survives interim updates and
  is spent on the final one, keeping ⏎ on the row the action touched.
- **`commit` holds `isApplyingPlan` for the whole draw**, not just the
  selection call — see gotcha #12, which is the app hanging outright.
- **A key the palette declines reports unhandled.** `route` returns
  `.passThrough` and the adapter propagates it, which is what lets ←/→ move the
  caret and ⌘C copy selected text out of the query field.
- **Quick Look focus uses explicit handoff state, never visibility.**
  `FocusLossCheck.decision` keeps a nil successor only while Quick Look is
  explicitly opening, and retries its resign handoff for a bounded interval.
  After that, nil is a genuine loss. Do not broaden this to “one of our overlays
  is visible”: the palette sits behind Large Type, and that rule stopped Large
  Type dismissing on an app switch. See gotcha #16 and
  [`ADR 0001`](docs/adr/0001-quick-look-focus-handoff.md). Dismissing an overlay
  re-keys the palette explicitly.
- **The actions panel stays non-key.** A non-activating child panel, so the
  query field keeps focus and the caret never needs freezing. Load-bearing for
  `FocusLossCheck`, whose allowlist excludes the plain `NSPanel` it is built
  from: were it to take key, that reads as focus loss and tears the palette
  down. A test pins both halves.
- **Storage is a `{version, payload}` envelope**, atomic, `0600`. A decode
  failure quarantines the file; `loadElements` decodes element-wise so one bad
  record doesn't cost the rest. Additive fields use `decodeIfPresent` — a
  version bump quarantines existing data.
- **`ClipboardCapturePolicy.sensitiveTypes` is the single place** deciding what
  is never recorded.
- **Pins are exempt from the history limit, not from everything.** They survive
  Clear and the trim, have their own cap, and the upstream-clear heuristic
  leaves them alone — it can't identify who cleared the pasteboard, so it must
  not delete something explicitly kept.
- **Currency provider traffic is consent-gated and defaults off.**
  `CurrencyProvider.isEnabled` defaults to `{ false }`, so an unwired consent
  check disables the fetch; consent is re-read on both sides of the network
  `await` because it can be withdrawn mid-flight. Turning it off deletes the
  cached rates. Released builds separately perform Sparkle update checks; see
  `docs/privacy.md`.
- **No Accessibility permission, ever.** Bopop neither pastes into other apps
  nor taps events. Scripts run via `Process` with absolute paths and no shell;
  `ActionRunner.allowedURL` allowlists `http`/`https`/`dict`.
- **Destructive commands confirm** — either macOS does it (the loginwindow
  events) or `SystemCommand.confirmation` does. The `…` title suffix marks
  exactly those, and a test pins it both ways.
