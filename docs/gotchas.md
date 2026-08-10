# Gotchas

Platform behaviour that cost real time to discover, and that reads as a bug or
as pointless code if you don't know it. Each of these has a load-bearing
workaround in the source; several are cited by number from the code, so keep
the numbering stable and append rather than renumber.

Extracted from a handover doc that was not tracked, which left three source
comments pointing at a file a fresh clone did not have.

1. **Cryptex apps are invisible to `FileManager.contentsOfDirectory`** on `/Applications`. Safari lives at `/System/Cryptexes/App/System/Applications` — it's in `AppCatalog.defaultDirectories`.
2. **Finder** isn't in any Applications dir; it's a single bundle at `/System/Library/CoreServices/Finder.app`, wired via `extraApplicationPaths`. Tests must pass `extraApplicationPaths: []` or real Finder pollutes fixtures.
3. **Apple Passwords sets no clipboard marker types** (macOS 15.7, verified) — only `public.utf8-plain-text`. It does fire a zero-type pasteboard clear ~60–90 s after the copy; the upstream-clear scrub (`forgetNewest(ifCapturedWithin:)`) keys off that. The window was narrowed from 600 s to 120 s in the `review-fixes` round (still comfortably wider than the observed 60–90 s, but re-QA the Apple Passwords case live before trusting it — see "Known pending manual QA"). Don't remove either layer.
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
