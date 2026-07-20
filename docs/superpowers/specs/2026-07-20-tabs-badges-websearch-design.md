# Tabs, Category Badges, Web Search — Design

Date: 2026-07-20. Approved by Jewei. Baseline: branch `feature/v2-answers` at `71a5dac`,
151 tests green.

## Goal

Three UI additions inspired by the Raycast-style filter bar:

1. Pill tab row under the query field — a visible, clickable mode switcher.
2. Per-row category badge on the right of each result.
3. A web-search fallback row, always last, with the engine configurable in Settings.

## Decisions made with the user

- Tabs and modes are ONE system: `All · Apps · Files · Clipboard · Emoji · Translate`.
  Clicking a tab enters the same sticky mode the prefixes/commands drive; prefixes
  keep working and highlight their tab. New `Mode.apps` = general search restricted
  to the apps provider.
- ⇥ / ⇧⇥ cycles tabs (spends the key previously reserved for a secondary-actions
  menu; ⌘K stays reserved for that). No ⌘-number shortcuts.
- The in-field mode chip is REMOVED — the active tab is the single mode indicator.
- Web row appears in All mode only, for any non-empty term, always pinned last.
  Return opens the engine's search URL in the default browser. Engines:
  Google (default) / DuckDuckGo / Bing / Brave, picked in Settings.
- Badges are monochrome (existing badge styling) — no per-category colors.

## Components

### Kit

- `Mode.apps` case. `QueryParser` unchanged otherwise (no prefix for apps; tab-only).
  `EscapePolicy` already handles any non-general mode → exitMode.
- `AppsProvider` additionally serves `.apps` mode (same behavior as general).
  All other providers ignore `.apps`.
- `ProviderID.webSearch` + `SearchEngine` enum (`google`, `duckDuckGo`, `bing`,
  `brave`; raw strings for defaults storage) with `searchURL(for term:) -> URL?`
  (percent-encoded query) and `displayName`.
- `WebSearchProvider(engine: @Sendable () -> SearchEngine)`: general mode + non-empty
  term → one result: title `Search <Engine> for "<term>"`, icon `magnifyingglass`,
  badge `Web`, action `.openURL(searchURL)`, keywords `[term]`.
- Ranker rule: `.webSearch` results bypass the tier filter and always sort last
  (explicit special case, unit-tested). Weight table entry not used for ordering.
- Badge derivation: `CategoryBadge.text(for result: SearchResult) -> String?` —
  returns `result.badge` if set, else per provider: apps "Apps", files "Files",
  clipboard "Clipboard", emoji "Emoji", webSearch "Web", scripts keeps its explicit
  "Script", commands/calculator/currency/time/urlClean/translation → nil (hero or
  self-evident rows).

### App target

- `PaletteTabsView`: pill row (~30 pt) between field hairline and hero/list.
  Active pill: `BrandColor` tinted fill; inactive: white 0.45 text, hover 0.7.
  Click → `onSelect(Mode)`. Exposes `setActive(Mode)`.
- `PaletteController`: owns tab↔mode sync (tab click, prefix typing, Esc, commands
  entering modes). ⇥/⇧⇥ handled via `insertTab`/`insertBacktab` in
  `control(_:textView:doCommandBySelector:)` → cycle mode. Mode chip removed.
  Panel height accounts for the tab row.
- `ResultRowView`: renders the derived category badge on the right (existing badge
  pipeline; only the derivation source changes).
- Settings: "Search engine" picker (4 engines), defaults key `searchEngine`,
  default Google, `storedSearchEngine(in:)` static reader.
  `AppDelegate` wires `WebSearchProvider` into `.general` with a closure reading
  that setting, and `AppsProvider` into a new `.apps` provider list.

## Error handling

- `searchURL` returning nil (unencodable term — practically unreachable) → provider
  returns `[]`.
- Tab row and modes can never disagree: mode is the single source of truth; the tab
  row is a pure function of it.

## Testing

Kit tests: Mode.apps escape chain; AppsProvider serves .apps; WebSearchProvider row
shape + per-engine URL encoding (spaces, CJK, `&`); Ranker pins webSearch last and
never filters it; CategoryBadge derivation table. UI: manual QA pass.

## Out of scope

⌘K secondary-actions menu, per-tab result counts, tab reordering, custom engines.
