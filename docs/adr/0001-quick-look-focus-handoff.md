# ADR 0001: Model Quick Look focus handoffs explicitly

- Status: accepted
- Date: 2026-08-12

## Context

When a Bopop overlay resigns key status, `NSApp.keyWindow` can be nil both when
the user genuinely switches away and while Quick Look is taking or returning
key status. Treating every nil as focus loss destroyed Quick Look. Treating a
visible Quick Look—or any visible Bopop overlay—as evidence of an internal
handoff created the opposite bug: visible overlays can coexist with a genuine
application switch, and the palette remains visible behind Large Type.

`NSApp.isActive` does not distinguish these paths for a non-activating panel in
an accessory application.

## Decision

Represent the lifecycle as `FocusHandoffState` instead of inferring it from
visibility:

- while Quick Look is explicitly opening, a nil successor remains internal;
- when Quick Look resigns, retry for a short bounded interval so AppKit can
  choose the next key window;
- a Bopop successor keeps focus;
- another window, a stable nil, or a nil that outlives the retry budget loses
  focus.

`FocusLossCheck.decision` owns this pure decision and the deferred runner owns
the retry. Callers must not invent visibility-based alternatives.

## Consequences

Quick Look can open and return key without tearing down the palette. Switching
away while Quick Look or Large Type is visible still dismisses Bopop. The retry
is bounded, so a missing successor cannot preserve an overlay indefinitely.
New focus-taking overlays must provide an explicit lifecycle signal or be
recognized as a concrete Bopop successor.
