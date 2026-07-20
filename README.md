# Bopop

A keyboard-first launcher for macOS. Press a shortcut, type, hit Return. Nothing else.

**Press. Type. Go.**

- ⌘Space (configurable) opens a floating palette over any Space or full-screen app
- A pill tab row (`All · Apps · Files · Clipboard · Emoji · Translate`) sits under the query field —
  click a tab, or cycle with ⇥/⇧⇥, to enter that mode; prefixes still work and highlight their tab
- Search and launch installed applications, ranked by match quality + how often you use them
- Type arithmetic (`2*(3+4)^2`) for an instant result — Return copies it
- `f <term>` or the Files tab for on-demand Spotlight file search (strictly opt-in, see below); optionally scope it to chosen folders in Settings — the inverse of Spotlight's Privacy exclusion list
- "Clipboard History…" for recent plain-text copies — Return re-copies
- Executables in the Scripts folder become searchable commands — run only on explicit Return
- Calculator, currency, timezone, and URL-cleaner answers render a hero card above the list — the
  rich, single-answer view Raycast users expect
- Currency conversion with cached ECB rates (`123myr to usd`) — instant from cache, refreshes quietly
  in the background when stale
- Timezone conversion (`9am eastern`, `time in tokyo`) — weekday and numeric-date phrases are rejected
  rather than mis-answered
- Emoji picker (`:fire` or "Emoji Picker…"), CLDR keyword search, frecency-ranked — Return copies
- URL tracking-parameter cleaner — paste a tracked link, Return opens the cleaned URL in your default
  browser instead of copying it
- Web search fallback — a "Search ⟨Engine⟩ for…" row is always pinned last in All mode for any
  non-empty query; Return opens it in your default browser. Choose the engine (Google, DuckDuckGo,
  Bing, Brave, YouTube, GitHub) in Settings; Bopop never fetches the search results itself
- Each result row carries a category badge (Apps/Files/Clipboard/Emoji/Web, or a provider's own
  explicit badge like Script) so mixed "All" results stay scannable
- English ⇄ Chinese translation (`t <text>` or "Translate…"), fully on-device via Apple's Translation
  framework — Return copies
- ⌘C copies the selected result's payload (path, value, text); Esc clears → exits mode → closes
- Drag the palette anywhere — it remembers the position across launches (falls back to center if the saved spot is offscreen)

## Build & run

Requires macOS 15+, Xcode 26 / Swift 6.2. No dependencies.

```sh
make test   # swift test — full suite
make app    # assemble + ad-hoc sign dist/Bopop.app
make run    # build, kill old instance, run inside the bundle (logs in terminal)
make open   # build and launch via Finder/LaunchServices
```

Bopop is a background agent (no Dock icon, no menu-bar item). Settings…, Open Scripts Folder, and Quit
live behind the gear button in the palette footer. If the hotkey ever stops responding, relaunching
Bopop (Finder, Spotlight, or `open -a Bopop`) shows the palette — the app is always reachable even
without a status item.

⌘Space is owned by Spotlight by default — Bopop detects this and offers a deep link to System Settings → Keyboard Shortcuts to disable Spotlight's binding, or record a different shortcut in Settings.

## Architecture

Two targets, one protocol, zero dependencies:

- **`BopopKit`** (library, Foundation + os only — no AppKit): all logic, fully unit-tested.
- **`Bopop`** (executable): thin AppKit shell — NSPanel palette, Carbon hotkey, footer gear menu, SwiftUI settings.

Data flow: keystroke → `QueryParser` (mode + term; `f ` prefix = file mode) → `QueryEngine` (generation counter; cancels the previous search task, debounces file mode 250 ms inside the task, runs the mode's providers concurrently) → results merge incrementally as each provider finishes (slow providers never block fast ones; a throwing provider is logged and isolated) → `Ranker` (match tiers exact > prefix > word-boundary > substring > subsequence, best-of across title + keywords, then provider weight, then frecency) → table → Return → `ActionRunner`.

Deliberate decisions:

- **Providers are one small protocol** (`ResultProvider`), not a plugin platform. Adding a provider = one file + one line of wiring.
- **AppKit palette, not SwiftUI**: a borderless `.nonactivatingPanel` (level `.statusBar`, `.fullScreenAuxiliary`) is the only way to reliably appear over full-screen apps without stealing the frontmost app's menu bar. SwiftUI is used where it's cheap: the Settings form.
- **Carbon `RegisterEventHotKey`** for the global shortcut: no Accessibility permission, consumes the event. All Carbon is confined to one file.
- **JSON files, not a database**: usage (≤500 ids) and clipboard history (≤500 entries) are tiny. `Storage` does versioned envelopes, atomic writes, 0600/0700 permissions, and quarantines corrupt files (`*.corrupt`) instead of crashing.
- **File search never indexes**: no catalog, no folder watching, no background scanning. An `NSMetadataQuery` (home scope, capped at 40 results, stop-after-gather) runs only while you're in file mode with a non-empty term, and is cancelled the moment the query changes or the mode exits.
- **Calculator is a hand-written recursive-descent parser** — not `NSExpression`, which can invoke arbitrary functions. Closed token set, typed errors, overflow-checked at every fold.

## Security & privacy

- Fully local, with one narrow, amended exception: currency conversion. A network call fires only
  while a currency query (`123myr to usd`) is being typed **and** the cached `rates.json` is more
  than 12 h old — a 5 s-timeout GET to `frankfurter.dev` (ECB reference rates, no API key, no
  tracking). A stale cache still answers instantly from disk; the refresh happens in the background,
  deduplicated so concurrent keystrokes never queue more than one in-flight request. With no cache
  and no connection, the row reads "Exchange rates unavailable — check connection" instead of
  guessing. No other feature makes a network call, ever — including translation, which runs on
  Apple's on-device Translation framework; the only network activity there is macOS's own
  language-model download consent flow, which Bopop triggers at most once per language pair per app
  run and never touches directly.
- Clipboard privacy has four layers: (1) apps marking `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` are never captured; (2) copies made while Apple Passwords or Keychain Access is frontmost are skipped using a heuristic, though a copy followed by an instant app switch within the 0.5 s poll can evade it; (3) a bare upstream clipboard clear (a zero-type change — Apple Passwords fires one ~90 s after a copy, including from its menu-bar popover, which layer 2 cannot see) retroactively removes the newest captured entry, so the secret does not outlive the clipboard, though it is visible in history during that pre-clear window; (4) "Clear Clipboard History" wipes the stored history on demand. Entries are capped at 100 KB; contents never appear in any log; `clipboard.json` is `-rw-------` inside a `drwx------` directory.
- Scripts (`~/Library/Application Support/Bopop/Scripts`): run only on explicit Return, never from typed input alone; executed directly via `Process` with an empty argv — no shell, no interpolation; rows carry a visible "Script" badge; output goes to `scripts.log` only. There is deliberately no timeout — a long-running script is legitimate.
- Permissions: nothing requested up front. Notification auth is requested on first script run; macOS file-access prompts appear only when you open a protected file. Accessibility is never requested.
- Logs use `os.Logger` with private interpolation for paths and queries.

## Testing

`swift test` — 162 tests over the parser, ranker (incl. the web-search pin-last rule), query/mode/escape rules, engine (stale-generation, cancellation, error isolation, incremental publish), stores (permissions, corruption, eviction), clipboard capture policy, app catalog (fixture bundles, `.apps` mode), script runner (real processes: exit codes, 200 KB stderr no-deadlock, stdin EOF, missing shebang), hero-card suppression, currency parsing/cross-rate math/staleness/refresh dedup, timezone parsing against a fixed clock, URL-cleaner rule tables, the emoji catalog and ranked search, translation direction detection/provider flow against a mock translator, web-search URL encoding per engine, and category-badge derivation.

Two live Spotlight tests are machine-dependent and opt-in: `BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live`.
