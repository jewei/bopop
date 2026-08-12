# Gotchas

Platform behaviour that cost real time to discover, and that reads as a bug or
as pointless code if you don't know it. Each of these has a load-bearing
workaround in the source; several are cited by number from the code, so keep
the numbering stable and append rather than renumber.

Extracted from a handover doc that was not tracked, which left three source
comments pointing at a file a fresh clone did not have.

1. **Cryptex apps are invisible to `FileManager.contentsOfDirectory`** on `/Applications`. Safari lives at `/System/Cryptexes/App/System/Applications` — it's in `AppCatalog.defaultDirectories`.
2. **Finder** isn't in any Applications dir; it's a single bundle at `/System/Library/CoreServices/Finder.app`, wired via `extraApplicationPaths`. Tests must pass `extraApplicationPaths: []` or real Finder pollutes fixtures.
3. **Apple Passwords sets no clipboard marker types** (macOS 15.7, verified) — only `public.utf8-plain-text`. It does fire a zero-type pasteboard clear ~60–90 s after the copy; the upstream-clear scrub (`forgetNewest(ifCapturedWithin:)`) keys off that. The window was narrowed from 600 s to 120 s in the `review-fixes` round, and a later live QA pass confirmed both the capture and the scrub. That pass also found the scrub was scoped wrong: Apple Passwords schedules its wipe **per copy**, but a second copy replaces the first on the pasteboard, so only one wipe actually lands. Scrubbing a single entry per wipe therefore left the earlier password in history permanently — reported as "i copied 2 passwords, 1 is gone, another 1 stays". `forgetCaptures(within:)` now drops every unpinned capture in the window, accepting that an unrelated copy made in the same window goes with them. Don't remove either layer.
4. **`NSTableRowView.isSelected` is set during row init**, before any cell exists — `view(atColumn:)` throws then, and Carbon event dispatch swallows the exception, presenting as a silent hang. The `guard numberOfColumns > 0` in `PaletteRowView` is load-bearing.
5. **Layer `cornerRadius` does not clip `NSVisualEffectView` blur material.** The rounded corners come from `maskImage` with `capInsets` in PaletteLayout.swift.
6. **`NSStackView(views:)` puts everything in the leading gravity area**; equal-priority ties break arbitrarily per cell reuse. Right-pinned views (badge, ↵ keycap) must be added with `addView(_, in: .trailing)`.
7. **`FileHandle.AsyncBytes` deadlocks on pipes** (macOS 15.7). ScriptRunner drains via `readabilityHandler` instead — don't "modernize" it back.
8. **Ad-hoc signing**: re-signing resets TCC/notification grants tied to the signature. Stable bundle path + id mitigates; if it bites, switch to a self-signed cert (one Makefile variable).
9. **`.translationTask(configuration:)` restarts its action task whenever the `configuration` value changes** — that kills a single-consumption `AsyncStream` bridge mid-flight (the drain loop is inside the action closure). `AppleTranslator` pins one immortal hidden host view + session per language pair instead of reconfiguring one shared session when the direction flips, so each stream lives for the process lifetime. Do not "simplify" this back to a single reconfigurable session — it silently drops in-flight requests every time the pair changes.
10. **`NSDataDetector` resolves relative/partial dates ("today", "tomorrow", missing year) against the real wall clock and `TimeZone.current`** — there is no injection API. `TimeQueryParser` only trusts the detector's time-of-day component and rebases the calendar day itself from an injected `now`, so tests stay on a fixed clock. Don't feed detector output straight through as an absolute date; it will drift when the machine's real clock differs from the test's fixed `now`.
11. **The query field's block cursor requires a TextKit 1 field editor.** Under TextKit 2 (the
    default field-editor mode since macOS 14) the caret is drawn by a separate
    `NSTextInsertionIndicator` subview and `drawInsertionPoint(in:)` is never called, so a custom
    block cursor silently never appears. `PalettePanel.fieldEditor(_:for:)` hands out a
    `BlockCursorTextView(usingTextLayoutManager: false)` explicitly to force TextKit 1. Don't drop
    that flag while "modernizing" the field editor.

12. **A palette draw must never re-enter a palette draw.** `reloadData()`
    changes an `NSTableView`'s selection and fires
    `tableViewSelectionDidChange` *synchronously*, so a guard around only the
    selection call lets the delegate mistake the reload for a user click and
    re-enter `PaletteController.commit` against half-updated views. That
    shipped once: the re-entrant pass reached the collection view while it
    still held the previous mode's items, AppKit wedged inside
    `scrollToItems`, and because the hung job was the engine's `Task`, the
    MainActor executor died with it — AppKit events kept flowing, so the UI
    looked alive while every later engine update was silently never
    delivered. Presented as "the emoji tab breaks every other tab".
13. **No test catches that class of bug.** `PaletteController` can be
    constructed and driven (`Tests/BopopTests/PaletteControllerTests.swift`),
    which covers wiring, but an off-screen `NSTableView` does not fire its
    selection delegate from `reloadData()` — reverting the guard leaves the
    suite green. A visible panel and changing row counts do not reproduce it
    either. Until there is a UI test host, a change to the palette's AppKit
    half wants a manual pass with `make run`.
14. **`PaletteController.show()` returns early when no screen owns the
    palette**, so `panel.isVisible` can never become true on a headless CI
    host. Assert dismissal on an observable that survives that —
    `hideCountForTesting` — or the test passes locally and fails on CI.
15. **`Sources/BopopKit/Resources/emoji.json` is generated**, not hand-edited.
    Regenerate with
    `swift Support/generate-emoji.swift > Sources/BopopKit/Resources/emoji.json`;
    it fetches from the network and the output is committed.
16. **A resigned key window with no successor does not mean the user left.**
    `NSApp.keyWindow` is nil both when another app is frontmost *and* during an
    in-app handover that has not settled — one deferred runloop turn is not
    enough for `QLPreviewPanel`, which takes key only after it has loaded its
    preview and gives it up again on the way out. Hiding on the bare nil tore
    the palette down mid-open and took Quick Look with it, presenting as "the
    pdf appears and then closes in 1 second". `NSApp.isActive` does not
    separate the two: it reads false in both. What separates them is whether
    one of Bopop's own overlays is still on screen — see
    `FocusLossCheck.isForeign(successor:ownPanel:quickLookIsVisible:)`.
    Quick Look **specifically**, not "any overlay of ours is visible": the
    palette sits visible behind every overlay, so the broad version stopped
    Large Type dismissing when the user switched away. Quick Look is the only
    overlay that takes key late, and the only one that cannot be subclassed to
    handle its own keys — `LargeTypePanel` overrides `performKeyEquivalent`
    instead, which is also why ⌘L could close it while ⌘Y needed the
    `previewPanel(_:handle:)` delegate hook.
