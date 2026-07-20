# Bopop

**Press. Type. Go.**

Bopop is a keyboard-first launcher for macOS. Hit a shortcut, type a few characters, press Return — an app opens, an answer appears, or a snippet lands on your clipboard. It floats over anything (any Space, even full-screen apps), stays out of your way, and does almost everything without ever touching the network.

## What it does

### Find and launch
- **Apps** — type a few letters, ranked by how well they match and how often you use them.
- **Files** — `f report` or the Files tab searches via Spotlight, strictly on demand: Bopop never builds an index and never watches folders. Want it narrower? Pick exactly which folders it may look in (Settings → File Search).
- **Scripts** — drop executables into the Scripts folder and they become searchable commands. They run only when you press Return, badged `Script` so you always know.
- **System commands** — `lock`, `sleep`, `restart`, `empty trash`, and friends. The destructive ones go through macOS's own confirmation dialog, not ours.

### Instant answers
Answers render as a hero card above the list — the big, single-answer view for when you asked a question, not for a list.

- **Calculator** — `2*(3+4)^2`, Return copies. Press ⇥ to feed the answer back into the query and keep going.
- **Currency** — `123myr to usd`, using cached ECB rates that refresh quietly in the background.
- **Time zones** — `9am eastern`, `time in tokyo`. Half-hour zones show their real offset.
- **Dictionary** — `define serendipity` (or `def`), fully on-device; Return opens the Dictionary app.
- **Translation** — `t 你好` translates English ⇄ Chinese on-device with Apple's Translation framework.
- **URL cleaner** — paste a link full of tracking parameters, Return opens the clean version.

### Clipboard, snippets & emoji
- **Clipboard history** — recent plain-text copies; Return re-copies. Password managers' concealed copies are never captured (more below).
- **Snippets** — save named text blocks in Settings → Snippets; they match by name or keyword right in All mode, or browse them all via "Snippets…". Return copies.
- **Emoji** — `:fire` or the Emoji tab opens a 10-column tile grid with keyword search and 2D arrow-key navigation. Return (or a click) copies.

### Search the web, your way
- A "Search ⟨Engine⟩ for…" row is always pinned last for any query — Return opens your browser. Pick the engine in Settings (Google, DuckDuckGo, Bing, Brave, YouTube, GitHub).
- Add your own keyword searches: a name, a keyword, and a `{query}` URL template turn `yt cute cats` into a one-keystroke search. Bopop opens the browser; it never fetches results itself.

## The keys

| Key | Does |
|---|---|
| ⌘Space (configurable) | Summon the palette |
| ⇥ / ⇧⇥ | Cycle the tabs (All · Apps · Files · Clipboard · Emoji · Translate) — or continue a calculation when an answer is showing |
| Return / click | Run the selected result |
| ⌘C | Copy the result's payload (text, value, path) |
| ⌘⏎ | Reveal a file result in Finder |
| ⌘Y | Quick Look a file result |
| ⌘L | Large Type — fill the screen with the answer; ⌘L, Esc, or a click dismisses |
| Esc | Clear the query → exit the mode → close, one step at a time |

Small comforts: the palette remembers where you dragged it, rows carry category badges so mixed results stay scannable, and the header keycap can be swapped for your own image (Settings → Appearance).

## Build & run

Requires macOS 15+, Xcode 26 / Swift 6.2. No dependencies.

```sh
make test   # swift test — full suite
make app    # assemble + ad-hoc sign dist/Bopop.app
make run    # build, kill old instance, run inside the bundle (logs in terminal)
make open   # build and launch via Finder/LaunchServices
```

Bopop is a background agent — no Dock icon, no menu-bar item. Settings, the Scripts folder, and Quit live behind the gear button in the palette footer. If the hotkey ever goes quiet, just launch Bopop again (Finder, Spotlight, or `open -a Bopop`) and the palette appears.

One heads-up: ⌘Space belongs to Spotlight out of the box. Bopop notices and offers a direct link to System Settings to free it up — or record any other shortcut you like.

## Privacy

Local-first is the whole point, so here's the honest inventory:

- **One network call, total.** Currency conversion fetches ECB reference rates from `frankfurter.dev` (no API key, no tracking) — and only while you're typing a currency query *and* the cached rates are older than 12 hours. No connection? You get "Exchange rates unavailable," not a guess. Nothing else ever goes online; translation runs entirely on-device.
- **Clipboard, four layers deep.** Concealed/transient pasteboard types (password managers) are never captured; copies from Apple Passwords or Keychain Access are skipped; a bare upstream clipboard clear retroactively removes the newest entry so a secret doesn't outlive the clipboard; and "Clear Clipboard History" wipes everything on demand. History lives in a `0600` file inside a `0700` directory and never appears in logs.
- **Scripts run only on Return** — directly via `Process`, empty argv, no shell, no interpolation. Output goes to a capped log file, nowhere else.
- **Permissions: almost none.** Nothing is requested up front. Notifications are asked for on first script run; two system commands (Empty Trash, Eject All) script Finder and trigger macOS's one-time Automation consent the first time you use them. Accessibility is never requested.

## Under the hood

Two targets, one protocol, zero dependencies:

- **`BopopKit`** — all the logic, Foundation-only, fully unit-tested (236 tests: parsers, ranker, engine, stores, providers).
- **`Bopop`** — a thin AppKit shell: the palette panel, the Carbon hotkey, SwiftUI settings.

A keystroke flows `QueryParser → QueryEngine → providers (concurrent, off the main actor — a slow one never blocks the rest) → Ranker → the list`, and Return hands the result to `ActionRunner`. Adding a capability means one provider file and one line of wiring — deliberately a small protocol, not a plugin platform.

A few choices worth knowing about:

- The palette is a borderless, non-activating AppKit panel — the only way to float over full-screen apps without stealing the front app's menu bar.
- The global hotkey uses Carbon's `RegisterEventHotKey`: no Accessibility permission needed.
- Storage is plain JSON with versioned envelopes, atomic writes, and quarantine-on-corruption — the data is tiny, and a database would be ceremony.
- The calculator is a hand-written parser with a closed token set — never `NSExpression`, which can call arbitrary functions.

Run the tests with `swift test`; two live Spotlight tests are opt-in via `BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live`.

## License

[MIT](LICENSE)
