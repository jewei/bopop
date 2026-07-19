# Bopop v2 Features — Design

Date: 2026-07-19. Approved by Jewei. Baseline: commit `f4d7e56`, 78 tests green.

## Goal

Seven additions that keep Bopop's core promise (press, type, go) while matching the
polish of Raycast's answer experience:

1. Hero result card (rich calculator-style answer panel)
2. Currency conversion (`123myr to usd`)
3. Timezone conversion (`9am eastern`, `time in tokyo`)
4. Emoji picker (`:fire`)
5. URL cleaner (paste URL → strip tracking params → Return opens in browser)
6. Translation, English ↔ Chinese (`t hello`), on-device
7. Remove the menu-bar status item; move Settings / Open Scripts Folder / Quit into
   the palette footer

## Decisions made with the user

- **Network**: amended invariant. Bopop may make network calls **only** to fetch
  exchange rates, **only** while a currency query is active and the cache is stale
  (>12 h). Everything else stays fully local.
- **Rates source**: frankfurter.dev (ECB reference rates, no API key). Cached via the
  existing `Storage` envelope; works offline from cache with an "updated X ago" note.
- **Translation**: Apple's on-device Translation framework. No third-party service.
  Chinese variant is a Settings choice, default Simplified. Chinese input auto-detects
  and translates to English.
- **Return action for emoji/translation**: copy to clipboard only. No auto-paste; the
  "never request Accessibility" invariant stands.

## Architecture

Approach: each feature is one `ResultProvider` plus one shared hero-card view.
No new abstraction layers (DI containers, converter registries — previously rejected,
still rejected).

### Hero card (`PaletteHeroView`, app target)

- `SearchResult` gains an optional `hero: HeroContent?` field.
  `HeroContent { left: String, leftBadge: String?, right: String, rightBadge: String?, note: String? }`
  (pure data, BopopKit, `Sendable`).
- When the **top-ranked** result has `hero != nil`, the palette renders the card
  between the query field and the results table: left pane (input + badge), center
  arrow + optional note, right pane (answer + badge). The result's normal row is
  suppressed from the table to avoid duplication.
- Calculator adopts it: left = expression + operation badge ("Product"/"Sum"/…),
  right = formatted result + spelled-out words via `NumberFormatter.Style.spellOut`.
- Currency, time, translation, and URL-clean results reuse the same card.
- Layout follows DESIGN.md "Minimal Mono"; corner masking must use the existing
  `maskImage` approach (gotcha #5), trailing-pinned elements use `.trailing` gravity
  (gotcha #6).

### Currency (`CurrencyProvider` + `CurrencyParser` + `RateStore`, BopopKit)

- New `ProviderID.currency`.
- `CurrencyParser` (pure): accepts `123myr to usd`, `100 usd in myr`, `€45 to rm`,
  `myr 250 to sgd`. Grammar: `<amount><code|symbol>` (spaces optional) + `to|in` +
  `<code|symbol>`. Symbol table: $ € £ ¥ ₩ ₹ RM plus ISO-4217 codes. Ambiguous `$`
  resolves to USD, `¥` to JPY.
- `RateStore`: persists `rates.json` (versioned envelope, 0600) holding EUR-base
  rates + fetch timestamp. Cross-pairs computed via EUR. Staleness threshold 12 h.
- `RateFetcher` (protocol seam for tests): production impl hits
  `https://api.frankfurter.dev/v1/latest?base=EUR` with a 5 s timeout; failures are
  isolated by the existing engine error handling.
- Behavior: parse hit + fresh cache → answer immediately. Stale cache → answer from
  cache immediately with "updated X ago" note, refresh in background, republish.
  No cache + offline → single row "Exchange rates unavailable — check connection".
- Return copies the numeric answer.

### Time (`TimeProvider` + `TimeQueryParser`, BopopKit)

- New `ProviderID.time`.
- `TimeQueryParser` (pure): two shapes —
  (a) `time in <place>` → current time in that zone;
  (b) `<datetime phrase> <zone token>` (e.g. `oct 13 9am eastern`, `9pm PST`) →
  that instant in the user's local zone. Datetime parsing via `NSDataDetector`;
  zone tokens via a table of abbreviations (EST/EDT/eastern/PST/…) and city names
  derived from `TimeZone.knownTimeZoneIdentifiers` (last path component, lowercased)
  plus common aliases (NYC, KL, SF…).
- Parser is injectable with a fixed `now` and fixed local `TimeZone` for tests.
- Hero card: left = parsed source ("Monday, 13 October, 9:00 AM, GMT-4"),
  right = local result + "Your Time" badge. Return copies the formatted local time.

### Emoji (`EmojiProvider` + `EmojiCatalog`, BopopKit)

- New `Mode.emoji`, prefix `:` (single colon + term, e.g. `:fire`), plus an
  "Emoji Picker…" command row that enters sticky emoji mode. Esc chain unchanged
  (clear → exit mode → close).
- Data: `emoji.json` committed under `Resources/`, generated once from CLDR
  annotations (emoji char, name, keywords, group). ~1,900 base emoji, no skin-tone
  expansion in v1. Loaded lazily, once.
- Search runs through the existing `Ranker` (name + keywords). Frecency applies via
  the existing `UsageStore` (id = emoji character).
- Row: emoji as leading "icon" (text attachment), name as title. Return copies the
  emoji. No hero card (list UX, like apps).

### URL cleaner (`URLCleanProvider` + `URLCleaner`, BopopKit)

- New `ProviderID.urlClean`. Triggers in general mode when the term parses as a
  http(s) URL with a host.
- `URLCleaner` (pure): removes query params matching a rule table —
  global: `utm_*`, `fbclid`, `gclid`, `gclsrc`, `dclid`, `msclkid`, `igshid`,
  `igsh`, `mc_eid`, `mc_cid`, `si`, `spm`, `vero_*`, `oly_*`, `_hsenc`, `_hsmi`,
  `wickedid`, `yclid`, `twclid`, `ttclid`, `s_kwcid`;
  per-host: amazon.* (`ref_`, `tag`, `pd_rd_*`, `pf_rd_*`, path `/ref=` segment),
  youtube (`si`, `pp`, `feature`). Fragment tracking (`#:~:text=` kept — that's a
  highlight, not tracking). Preserves param order of survivors.
- Hero card: left = original (truncated middle), right = cleaned URL, badge shows
  "N trackers removed" (or provider yields nothing if URL was already clean —
  no card, no noise). Return opens cleaned URL via `NSWorkspace` (default browser);
  ⌘C copies it. New `ResultAction.openURL(String)`.

### Translation (`TranslationProvider`, app target; `TranslationQueryParser` in Kit)

- New `ProviderID.translation`, prefix `t ` (like `f `), plus "Translate…" command
  entering sticky mode.
- Direction: if the term contains Han characters → target English; otherwise →
  Chinese, variant from Settings (`zh-Hans` default, `zh-Hant` optional).
- Engine: Apple Translation framework (`import Translation`). The provider lives in
  the **app target** because `TranslationSession` must be obtained through a SwiftUI
  `.translationTask` host; a hidden 0×0 hosting view owns the session. BopopKit
  defines a `Translator` protocol (async `translate(text, from, to) -> String`) so
  the parser/provider logic is testable with a mock.
- Debounce 300 ms inside the provider task (mirrors file-search's 250 ms pattern).
  First-ever use triggers the system language-model download prompt; while models
  are unavailable the provider yields a row "Download Chinese ⇄ English translation…"
  whose action triggers the download flow.
- Hero card: left = source text + detected-language badge, right = translation +
  target badge. Return copies the translation.

### Menu-bar removal (app target)

- Status item code deleted. `PaletteFooterView` gains a trailing gear button
  (gotcha #6: `.trailing` gravity) opening an `NSMenu`: Settings…, Open Scripts
  Folder, Clear Clipboard History, Quit Bopop.
- Failsafe: `applicationShouldHandleReopen` shows the palette, so relaunching the
  app (Finder/Spotlight/`open -a Bopop`) always recovers even if the hotkey is
  broken. Spotlight-conflict onboarding flow unchanged.

## Wiring

- `QueryParser` learns `:` (emoji) and `t ` (translation) prefixes; `Mode` gains
  `emoji`, `translation`. Currency/time/URL-clean run in **general** mode alongside
  apps/calculator (they self-select by parsing the term, returning `[]` on no match,
  exactly like calculator today).
- Ranking: hero results get a `sortHint` above apps so the card claims the top slot
  whenever its parser matches.

## Error handling

- Network failure → cached rates or a single explanatory row; never a thrown error
  reaching the UI (engine already isolates throwing providers).
- Translation model missing → actionable download row.
- All parsers return `nil`/`[]` on non-matching input — silent, zero-cost.

## Testing

Kit unit tests (target additions, all deterministic):
- `CurrencyParser` (codes, symbols, RM alias, spacing, garbage rejection)
- `RateStore` (staleness, cross-rate math, corruption quarantine, permissions)
- `TimeQueryParser` (fixed now/zone: abbreviations, cities, `time in X`, DST edges)
- `URLCleaner` (each rule class, per-host rules, already-clean passthrough,
  non-URL rejection, survivor order)
- `EmojiCatalog` (load, keyword search via Ranker, frecency integration)
- `QueryParser` new prefixes + Esc chain for new modes
- Translation direction detection + mock-`Translator` provider flow
- Hero suppression rule (top result with hero doesn't duplicate into table rows)

App-target behavior (manual QA): hero card rendering, gear menu, reopen failsafe,
first-run model download, live rate fetch.

## Out of scope (unchanged deferrals)

Skin-tone variants, auto-paste, clipboard images, script args, themes, plugin SDK.

## Documentation updates

README (features, invariant amendment, test count), HANDOVER (new gotchas if any),
PRODUCT.md feature list, DESIGN.md hero-card spec.
