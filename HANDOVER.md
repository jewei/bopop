# Handover

State of the project as of 2026-07-20, v2 feature branch (`feature/v2-answers`) merged, plus the
tabs/badges/web-search follow-on. 162 tests green.

## Where things stand

- v2 added five new answer providers (currency, timezone, emoji, URL cleaner, translation), a shared
  hero answer card, and removed the menu-bar status item in favor of a footer gear menu. See
  `git log --oneline 6cd8638..HEAD` for the 13-commit sequence (Conventional Commits throughout).
- A follow-on unified the in-field mode chip with a visible pill tab row (`All · Apps · Files ·
  Clipboard · Emoji · Translate`), added per-row category badges, and added a configurable
  web-search fallback row. See `git log --oneline c610e98..HEAD` (5 commits) and
  `docs/superpowers/specs/2026-07-20-tabs-badges-websearch-design.md`. The old in-field mode chip
  (`PaletteModeChipView`) is gone — the tab row is now the single mode indicator. ⇥/⇧⇥ is spent
  cycling tabs; the "Tab/⌘K secondary-actions menu" idea in the deferred list below is now ⌘K only.
- Eleven providers live: apps, calculator, opt-in file search, clipboard history, user scripts,
  currency, timezone, emoji, URL cleaner, translation, web search — each still one file + one line
  of wiring, no plugin layer. `Mode.apps` (tab-only, no prefix) restricts search to the apps
  provider; `AppsProvider` serves both `.general` and `.apps` identically.
- Design v2 "Minimal Mono" applied (see DESIGN.md), extended with the hero-card spec and the tab-row
  spec; custom app icon in `Resources/AppIcon.icns`.
- Manual QA (v1 MVP) passed end-to-end: hotkey over full-screen, `fs_usage` audit (zero mds traffic
  outside file mode), clipboard privacy including the Apple Passwords menu-bar popover case, Esc
  chain, Settings hotkey recorder, drag-position persistence across relaunch.
- Manual QA (v2, partial — see "Known pending manual QA" below): gear menu opens Settings and quits
  correctly, `open -a Bopop` while running shows the palette (reopen failsafe), hotkey still works,
  currency/timezone/URL/emoji hero cards and rows confirmed via `screencapture`. Translation mode
  rendering, the Settings Chinese-variant picker, and the footer gear glyph/hover state were **not**
  visually verified — the screen was locked during that portion of agent QA.
- Idle footprint: ~0.0 % CPU, ~32 MB RSS (v1 baseline; not re-measured with the new providers, but
  currency/timezone/URL/emoji are all pure-CPU parsers and translation only runs on typed input, so
  no change expected).

## Build & run

See README.md. Short version: `make test` / `make app` / `make run` / `make open`. No dependencies, no .xcodeproj — SPM + Makefile assembles and ad-hoc signs `dist/Bopop.app`.

Live Spotlight tests (machine-dependent): `BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live`.

## Debugging toolkit (all proven in anger)

- `BOPOP_DEBUG_AUTOSHOW=1 dist/Bopop.app/Contents/MacOS/Bopop` — opens the palette 0.5 s after launch. Headless UI repro without a keyboard; this is how the row-init crash was caught.
- Window probing: `CGWindowListCopyWindowInfo` via `swift -e` to confirm the panel is onscreen and where.
- Visual verification: `screencapture -x -R <x,y,w,h>` of the panel region, then Read the png.
- Exception trapping: `lldb --batch -p <pid> -o 'breakpoint set -E objc' -o continue` — AppKit assertions thrown inside Carbon event dispatch are swallowed silently; this is the only way to see them.
- Logs: use `/usr/bin/log` explicitly — zsh has a `log` builtin that shadows it and silently returns nothing.
- Pasteboard forensics: dump `NSPasteboard.general.types` on a timer to see marker types and upstream clears without ever reading contents.

## Hard-won gotchas (do not relearn these)

1. **Cryptex apps are invisible to `FileManager.contentsOfDirectory`** on `/Applications`. Safari lives at `/System/Cryptexes/App/System/Applications` — it's in `AppCatalog.defaultDirectories`.
2. **Finder** isn't in any Applications dir; it's a single bundle at `/System/Library/CoreServices/Finder.app`, wired via `extraApplicationPaths`. Tests must pass `extraApplicationPaths: []` or real Finder pollutes fixtures.
3. **Apple Passwords sets no clipboard marker types** (macOS 15.7, verified) — only `public.utf8-plain-text`. It does fire a zero-type pasteboard clear ~60–90 s after the copy; the upstream-clear scrub (`forgetNewest(ifCapturedWithin: 600)`) keys off that. Don't remove either layer.
4. **`NSTableRowView.isSelected` is set during row init**, before any cell exists — `view(atColumn:)` throws then, and Carbon event dispatch swallows the exception, presenting as a silent hang. The `guard numberOfColumns > 0` in `PaletteRowView` is load-bearing.
5. **Layer `cornerRadius` does not clip `NSVisualEffectView` blur material.** The rounded corners come from `maskImage` with `capInsets` in PaletteLayout.swift.
6. **`NSStackView(views:)` puts everything in the leading gravity area**; equal-priority ties break arbitrarily per cell reuse. Right-pinned views (badge, ↵ keycap) must be added with `addView(_, in: .trailing)`.
7. **`FileHandle.AsyncBytes` deadlocks on pipes** (macOS 15.7). ScriptRunner drains via `readabilityHandler` instead — don't "modernize" it back.
8. **Ad-hoc signing**: re-signing resets TCC/notification grants tied to the signature. Stable bundle path + id mitigates; if it bites, switch to a self-signed cert (one Makefile variable).
9. **`.translationTask(configuration:)` restarts its action task whenever the `configuration` value changes** — that kills a single-consumption `AsyncStream` bridge mid-flight (the drain loop is inside the action closure). `AppleTranslator` pins one immortal hidden host view + session per language pair instead of reconfiguring one shared session when the direction flips, so each stream lives for the process lifetime. Do not "simplify" this back to a single reconfigurable session — it silently drops in-flight requests every time the pair changes.
10. **`NSDataDetector` resolves relative/partial dates ("today", "tomorrow", missing year) against the real wall clock and `TimeZone.current`** — there is no injection API. `TimeQueryParser` only trusts the detector's time-of-day component and rebases the calendar day itself from an injected `now`, so tests stay on a fixed clock. Don't feed detector output straight through as an absolute date; it will drift when the machine's real clock differs from the test's fixed `now`.

## Storage & settings surface

- `~/Library/Application Support/Bopop/` — `usage.json`, `clipboard.json`, `rates.json`, `Scripts/`, `scripts.log`. Versioned JSON envelopes; corrupt files are renamed `*.corrupt` and skipped, never crash. `rates.json` (EUR-base ECB rates + fetch timestamp) follows the same pattern: `-rw-------` (0600), versioned envelope, quarantine-on-corrupt like everything else in `Storage`.
- UserDefaults (`com.oneone.bopop`): hotkey config, clipboard limit, palette position (`palettePositionTopLeftX/Y` — saved only after a user drag, ignored if offscreen at restore), `chineseVariant` (raw `TranslationTarget` string, default `zh-Hans`), `searchEngine` (raw `SearchEngine` string, default `google`; picker in Settings, 380×360 now that the search-engine row added height).

## Deferred (explicitly out of MVP — don't assume they're missing by accident)

- Script arguments (argv is deliberately empty — security posture).
- ⌘K secondary-actions menu (`Result.secondaryActions` field exists; only ⌘C wired; footer reserves
  ⌘K). ⇥/⇧⇥ is no longer available for this — it now cycles the tab row.
- Clipboard images (plain text only), file-content search, themes, auto-update, plugin SDK.
- Per-tab result counts, tab reordering, custom search engines.
- VoiceOver spot-check (labels exist and are wired; never manually audited).
- SQLite (JSON confirmed sufficient — rejected decision, don't reintroduce; likewise DI containers and storage-protocol layers).
- Emoji skin tones (v1 catalog is base emoji only, ~1,900 entries, no skin-tone expansion).
- Translation model download UX is a single informational row ("Download Chinese ⇄ English translation…"); it does not track download progress. The system's own consent/download prompt auto-fires at most once per language pair per app run — Bopop doesn't build a custom download flow around it.

## Known pending manual QA

Agent QA for v2 covered hero cards (calculator/currency/timezone/URL/emoji), the gear menu, and the
reopen failsafe via `screencapture`, but the screen was locked for part of the session. Not yet
visually verified by a human: translation-mode hero rendering, the Settings Chinese-variant picker,
and the footer gear glyph/hover states. Functionally exercised by tests and by the parts of agent QA
that did run, but worth a real look before calling v2 done.

Tabs/badges/web-search follow-on: agent QA live-verified the tab row itself (click, prefix highlight,
⇥ cycling, Esc) via `BOPOP_DEBUG_AUTOSHOW`. The per-row category badges, the "Search ⟨Engine⟩ for…"
row rendering last with a "Web" badge, opening it in the browser, and the Settings search-engine
picker (including the new 360 pt form height) were only build+test verified, not visually confirmed
live — worth a real look alongside the still-pending v2 items above.

## Invariants to preserve

- Clipboard contents never appear in any log, ever.
- Scripts run only on explicit Return, via `Process` with direct `executableURL` and empty argv — no shell anywhere.
- No `NSExpression` in the calculator.
- File search never indexes, scans, or watches — `NSMetadataQuery` on demand only, cancelled on mode exit.
- Accessibility permission never requested; no third-party dependencies; no bundled fonts.
- **Network (amended in v2):** fully local except one narrow case — exchange-rate fetch. A request to
  `frankfurter.dev` (ECB reference rates) fires only while a currency query is being typed **and**
  the cached `rates.json` is more than 12 h old; a stale cache still answers instantly and refreshes
  once in the background (`refreshInFlight` guard in `Currency.swift` dedupes concurrent keystrokes
  to a single in-flight request); no cache + offline degrades to an "unavailable" row rather than
  hanging or guessing. No other provider, anywhere, makes a network call. Translation runs on Apple's
  on-device Translation framework; the only network activity there is macOS's own language-model
  download consent flow, which Bopop triggers (via `requestDownload`/`prepareTranslation`) at most
  once per language pair per app run — Bopop never talks to a translation server itself. The
  web-search row (`WebSearchProvider`) doesn't change this invariant: Bopop only builds the search
  URL and hands it to `NSWorkspace.open` on Return — it never fetches the URL or the engine's results
  itself.
