# Handover

State of the project as of 2026-07-19, commit `601317c`. MVP is complete: all planned features shipped, 78 tests green, every user-reported issue fixed and verified.

## Where things stand

- 21 commits, `89a6011` → `601317c`, Conventional Commits throughout (security fixes carry explanatory bodies).
- All five providers live: apps, calculator, opt-in file search, clipboard history, user scripts.
- Design v2 "Minimal Mono" applied (see DESIGN.md); custom app icon in `Resources/AppIcon.icns`.
- Manual QA passed end-to-end: hotkey over full-screen, `fs_usage` audit (zero mds traffic outside file mode), clipboard privacy including the Apple Passwords menu-bar popover case, Esc chain, Settings hotkey recorder, drag-position persistence across relaunch.
- Idle footprint: ~0.0 % CPU, ~32 MB RSS. Data files `-rw-------` in a `drwx------` dir.

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

## Storage & settings surface

- `~/Library/Application Support/Bopop/` — `usage.json`, `clipboard.json`, `Scripts/`, `scripts.log`. Versioned JSON envelopes; corrupt files are renamed `*.corrupt` and skipped, never crash.
- UserDefaults (`com.oneone.bopop`): hotkey config, clipboard limit, palette position (`palettePositionTopLeftX/Y` — saved only after a user drag, ignored if offscreen at restore).

## Deferred (explicitly out of MVP — don't assume they're missing by accident)

- Script arguments (argv is deliberately empty — security posture).
- Tab/⌘K secondary-actions menu (`Result.secondaryActions` field exists; only ⌘C wired; footer reserves ⌘K).
- Clipboard images (plain text only), file-content search, themes, auto-update, plugin SDK.
- VoiceOver spot-check (labels exist and are wired; never manually audited).
- SQLite (JSON confirmed sufficient — rejected decision, don't reintroduce; likewise DI containers and storage-protocol layers).

## Invariants to preserve

- Clipboard contents never appear in any log, ever.
- Scripts run only on explicit Return, via `Process` with direct `executableURL` and empty argv — no shell anywhere.
- No `NSExpression` in the calculator.
- File search never indexes, scans, or watches — `NSMetadataQuery` on demand only, cancelled on mode exit.
- Accessibility permission never requested; no network calls; no third-party dependencies; no bundled fonts.
