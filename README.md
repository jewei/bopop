# Bopop

A keyboard-first launcher for macOS. Press a shortcut, type, hit Return. Nothing else.

**Press. Type. Go.**

- ⌘Space (configurable) opens a floating palette over any Space or full-screen app
- Search and launch installed applications, ranked by match quality + how often you use them
- Type arithmetic (`2*(3+4)^2`) for an instant result — Return copies it
- `f <term>` or "Search Files…" for on-demand Spotlight file search (strictly opt-in, see below)
- "Clipboard History…" for recent plain-text copies — Return re-copies
- Executables in the Scripts folder become searchable commands — run only on explicit Return
- ⌘C copies the selected result's payload (path, value, text); Esc clears → exits mode → closes

## Build & run

Requires macOS 15+, Xcode 26 / Swift 6.2. No dependencies.

```sh
make test   # swift test — full suite
make app    # assemble + ad-hoc sign dist/Bopop.app
make run    # build, kill old instance, run inside the bundle (logs in terminal)
make open   # build and launch via Finder/LaunchServices
```

Bopop is a menu-bar agent (no Dock icon). The status item menu has Show, Settings…, Open Scripts Folder, Quit.

⌘Space is owned by Spotlight by default — Bopop detects this and offers a deep link to System Settings → Keyboard Shortcuts to disable Spotlight's binding, or record a different shortcut in Settings.

## Architecture

Two targets, one protocol, zero dependencies:

- **`BopopKit`** (library, Foundation + os only — no AppKit): all logic, fully unit-tested.
- **`Bopop`** (executable): thin AppKit shell — NSPanel palette, Carbon hotkey, status item, SwiftUI settings.

Data flow: keystroke → `QueryParser` (mode + term; `f ` prefix = file mode) → `QueryEngine` (generation counter; cancels the previous search task, debounces file mode 250 ms inside the task, runs the mode's providers concurrently) → results merge incrementally as each provider finishes (slow providers never block fast ones; a throwing provider is logged and isolated) → `Ranker` (match tiers exact > prefix > word-boundary > substring > subsequence, best-of across title + keywords, then provider weight, then frecency) → table → Return → `ActionRunner`.

Deliberate decisions:

- **Providers are one small protocol** (`ResultProvider`), not a plugin platform. Adding a provider = one file + one line of wiring.
- **AppKit palette, not SwiftUI**: a borderless `.nonactivatingPanel` (level `.statusBar`, `.fullScreenAuxiliary`) is the only way to reliably appear over full-screen apps without stealing the frontmost app's menu bar. SwiftUI is used where it's cheap: the Settings form.
- **Carbon `RegisterEventHotKey`** for the global shortcut: no Accessibility permission, consumes the event. All Carbon is confined to one file.
- **JSON files, not a database**: usage (≤500 ids) and clipboard history (≤500 entries) are tiny. `Storage` does versioned envelopes, atomic writes, 0600/0700 permissions, and quarantines corrupt files (`*.corrupt`) instead of crashing.
- **File search never indexes**: no catalog, no folder watching, no background scanning. An `NSMetadataQuery` (home scope, capped at 40 results, stop-after-gather) runs only while you're in file mode with a non-empty term, and is cancelled the moment the query changes or the mode exits.
- **Calculator is a hand-written recursive-descent parser** — not `NSExpression`, which can invoke arbitrary functions. Closed token set, typed errors, overflow-checked at every fold.

## Security & privacy

- Fully local. No telemetry, no analytics, no network calls.
- Clipboard privacy has four layers: (1) apps marking `org.nspasteboard.ConcealedType` or `org.nspasteboard.TransientType` are never captured; (2) copies made while Apple Passwords or Keychain Access is frontmost are skipped using a heuristic, though a copy followed by an instant app switch within the 0.5 s poll can evade it; (3) a bare upstream clipboard clear (a zero-type change — Apple Passwords fires one ~90 s after a copy, including from its menu-bar popover, which layer 2 cannot see) retroactively removes the newest captured entry, so the secret does not outlive the clipboard, though it is visible in history during that pre-clear window; (4) "Clear Clipboard History" wipes the stored history on demand. Entries are capped at 100 KB; contents never appear in any log; `clipboard.json` is `-rw-------` inside a `drwx------` directory.
- Scripts (`~/Library/Application Support/Bopop/Scripts`): run only on explicit Return, never from typed input alone; executed directly via `Process` with an empty argv — no shell, no interpolation; rows carry a visible "Script" badge; output goes to `scripts.log` only. There is deliberately no timeout — a long-running script is legitimate.
- Permissions: nothing requested up front. Notification auth is requested on first script run; macOS file-access prompts appear only when you open a protected file. Accessibility is never requested.
- Logs use `os.Logger` with private interpolation for paths and queries.

## Testing

`swift test` — 73 tests over the parser, ranker, query/mode/escape rules, engine (stale-generation, cancellation, error isolation, incremental publish), stores (permissions, corruption, eviction), clipboard capture policy, app catalog (fixture bundles), and script runner (real processes: exit codes, 200 KB stderr no-deadlock, stdin EOF, missing shebang).

Two live Spotlight tests are machine-dependent and opt-in: `BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live`.
