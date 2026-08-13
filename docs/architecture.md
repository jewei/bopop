# Architecture

Bopop is a SwiftPM macOS application with two targets:

- `BopopKit` owns domain logic: parsing, providers, ranking, palette state,
  storage, scripts, and preferences. It intentionally avoids AppKit and SwiftUI.
  It may use non-UI Apple modules such as Foundation, `os`, and
  UniformTypeIdentifiers.
- `Bopop` owns the macOS adapter: AppKit panels, SwiftUI Settings, Carbon hotkey,
  pasteboard observation, translation UI, Sparkle, and action side effects.

SwiftPM enforces the dependency direction (`Bopop` depends on `BopopKit`). The
“no UI framework in BopopKit” rule is a review convention, not something SwiftPM
enforces by itself.

## Query and rendering flow

```text
input
  ↓
PaletteController (AppKit adapter)
  ↓
PaletteState → QueryEngine → Providers (concurrent) → Ranker
  ↑                                                   │
  └────────────── PaletteRenderPlan ← results ────────┘
  ↓
PaletteController.commit(plan) → views and ActionRunner
```

`PaletteState` is the sole owner of Foundation-representable palette state:
query, effective mode, results, hero content, focus, restoration, and redraw
identity. Every state command returns a `PaletteRenderPlan`. The controller
commits that plan to AppKit and executes its effects; it does not become a
second state owner.

The controller holds `isApplyingPlan` for the complete AppKit draw. AppKit can
synchronously fire selection callbacks during `reloadData()`, so shortening the
guard permits a re-entrant draw and can wedge the main actor. See gotchas 12–13.

## Composition and concurrency

`AppDelegate.init()` is the composition root for long-lived state. Dependencies
are constructed there and passed by initializer or closure. There is no DI
container.

Providers run concurrently in `QueryEngine`. A provider that needs main-actor
state receives an explicit snapshot; it must not reach through UI objects from
provider work. Parsed queries travel into the engine and return on each update,
so stale results can be rejected without reparsing against a second clock.

## State and persistence

User defaults hold small preferences keyed by bundle identifier. Domain records
use versioned JSON envelopes with atomic, mode-`0600` writes. Element-wise
decoding salvages valid records; an unreadable file is quarantined. Additive
fields should use `decodeIfPresent`; bumping the storage envelope version is a
migration decision, not a routine field addition.

Source builds use the `.dev` bundle identifier through `make run` and
`make open`. Preferences, login-item state, Sparkle state, and Application
Support therefore remain separate from an installed release.

## Where changes belong

- Parsing, ranking, provider decisions, state transitions, and persistence:
  `Sources/BopopKit`.
- macOS event decoding, window behavior, side effects, and framework adapters:
  `Sources/Bopop`.
- Exact palette geometry and color constants: `PaletteMetrics.swift`,
  `BrandColor.swift`, and the relevant view implementation.
- A platform workaround that looks removable: source comment plus an appended
  entry in `docs/gotchas.md`.
- A durable cross-module decision: an ADR under `docs/adr`.

Prefer one owner and direct calls. Extract a helper when it has a second caller
or owns a coherent domain rule—not solely to make one implementation detail
mockable.
