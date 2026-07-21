# Bopop

**Press. Type. Go.**

Bopop is a fast, keyboard-first launcher for macOS. Open apps, search files on demand, run scripts, calculate, translate, browse clipboard history, and more — without AI clutter.

## Features

- **Apps** — fuzzy search with usage-based ranking.
- **Files** — search through Spotlight only when requested. Bopop does not build its own index or watch folders.
- **Scripts** — place executables in the Scripts folder and run them explicitly.
- **System commands** — lock, sleep, restart, empty Trash, and more.
- **Calculator** — evaluate expressions and copy results.
- **Currency** — convert currencies using cached ECB rates.
- **Time zones** — convert times and inspect local time around the world.
- **Dictionary** — look up words on-device.
- **Translation** — English and Chinese translation using Apple’s Translation framework.
- **URL cleaner** — remove common tracking parameters.
- **Clipboard history** — browse and re-copy recent plain-text entries.
- **Snippets** — save and search reusable text.
- **Emoji** — search and copy emoji with keyboard navigation.
- **Web search** — use built-in or custom search engines.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘Space` | Open Bopop |
| `⇥` / `⇧⇥` | Switch tabs |
| `⏎` | Run selected result |
| `⌘K` | Actions for the selected result — copy, reveal in Finder, Quick Look, Large Type |
| `Esc` | Clear, exit mode, or close |

The global shortcut is configurable.

## Build

Requires macOS 15+, Xcode 26, and Swift 6.2. Bopop has no third-party dependencies.

```sh
make test   # swift test — full suite
make app    # assemble + ad-hoc sign dist/Bopop.app
make run    # build, kill old instance, run inside the bundle (logs in terminal)
make open   # build and launch via Finder/LaunchServices
```

Bopop runs as a background agent with no Dock icon or menu-bar item. Open Settings, Scripts, or Quit from the gear button in the launcher.

Because macOS uses `⌘Space` for Spotlight by default, you may need to disable that shortcut in System Settings or choose another one for Bopop.

## Privacy

Bopop is local-first.

- File search runs only when requested.
- Translation runs on-device.
- Clipboard entries marked concealed or transient are ignored.
- Clipboard history is stored locally and can be cleared at any time.
- Scripts run only after explicit confirmation with `Return`.
- Scripts use `Process` directly, without shell interpolation.
- Accessibility permission is not required.
- Currency conversion is the only network-backed feature and uses cached exchange rates.

## Architecture

Bopop has two targets:

- **BopopKit** — parsers, ranking, providers, storage, and core logic.
- **Bopop** — the AppKit launcher window, global hotkey, and SwiftUI settings.

Queries flow through:

```text
QueryParser → QueryEngine → Providers → Ranker → Results → ActionRunner
```

Providers run concurrently so slower features do not block faster ones.

Implementation details:

- AppKit borderless panel for reliable display over Spaces and full-screen apps.
- Carbon `RegisterEventHotKey` for the global shortcut.
- Versioned JSON storage with atomic writes.
- Hand-written calculator parser with a closed token set.
- No plugin platform and no third-party dependencies.

Run the full test suite with:

```sh
swift test
```

Live Spotlight tests are optional:

```sh
BOPOP_LIVE_SPOTLIGHT=1 swift test --filter live
```

## License

[MIT](LICENSE)
