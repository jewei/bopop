# Bopop v2 Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hero answer card + five new answer providers (currency, time, emoji, URL cleaner, translation) + menu-bar removal, per `docs/superpowers/specs/2026-07-19-bopop-v2-features-design.md`.

**Architecture:** Each feature is one `ResultProvider` following the `CalculatorProvider` self-selection pattern (parse the term, return `[]` on no match). One shared `PaletteHeroView` renders any result carrying `HeroContent`. Task 1 lands all shared-file plumbing (enums, prefixes, weights); Tasks 2–6 are pure-Kit, file-disjoint, and safe to implement in parallel; Tasks 7–9 are app-target UI, sequential.

**Tech Stack:** Swift 6.2, SPM, macOS 15+, zero third-party dependencies. Apple `Translation` framework (app target only). `swift-testing` (`@Test`/`#expect`) — match existing tests in `Tests/BopopKitTests/`.

## Global Constraints

- Swift 6 strict concurrency; both targets build with `.defaultIsolation(MainActor.self)`; Kit types stay `nonisolated` + `Sendable` like existing ones.
- BopopKit imports Foundation + os ONLY. No AppKit, no Translation framework in Kit.
- Network: ONLY `RateFetcher` may touch the network, only when a currency query is active and cache >12 h old. 5 s timeout.
- Clipboard/translation/query contents never logged. `os.Logger` private interpolation for anything user-derived.
- No `NSExpression`. No Accessibility. No auto-paste. Return copies (except URL cleaner: Return opens).
- All files written via `Storage` (versioned envelope, 0600/0700).
- TDD every task: failing test → implement → green. `swift test` full suite green before every commit. Conventional Commits.
- UI: corner masking via existing `maskImage` approach; right-pinned stack views use `.trailing` gravity (HANDOVER gotchas #5, #6). Fonts/colors per DESIGN.md "Minimal Mono" — monospaced system font, white-alpha hierarchy, `BrandColor` accent.

---

### Task 1: Core plumbing (shared files — must land before all others)

**Files:**
- Modify: `Sources/BopopKit/Result.swift` (ProviderID, ResultAction, HeroContent, SearchResult.hero)
- Modify: `Sources/BopopKit/Query.swift` (Mode cases, prefixes)
- Modify: `Sources/BopopKit/Ranker.swift` (defaultWeights)
- Modify: `Sources/BopopKit/Calculator.swift` (hero adoption)
- Modify: `Sources/BopopKit/Commands.swift` (two new command rows)
- Create: `Sources/BopopKit/HeroPresentation.swift`
- Test: `Tests/BopopKitTests/HeroTests.swift`, extend existing `QueryTests`/calculator tests

**Interfaces (Produces — later tasks depend on these exact names):**

```swift
// Result.swift additions
public nonisolated enum ProviderID: String { /* + */ case currency, time, emoji, urlClean, translation }
public nonisolated enum ResultAction { /* + */ case openURL(String) }

public nonisolated struct HeroContent: Equatable, Sendable {
    public let left: String
    public let leftBadge: String?
    public let right: String
    public let rightBadge: String?
    public let note: String?
    public init(left: String, leftBadge: String? = nil, right: String,
                rightBadge: String? = nil, note: String? = nil)
}
// SearchResult gains `public let hero: HeroContent?`, default nil, placed before sortHint in init.

// Query.swift additions
public nonisolated enum Mode: String { /* + */ case emoji, translation }
// QueryParser: in general sticky mode, "t " prefix → .translation (same shape as "f ");
// a leading ":" with at least one following char → .emoji with term = rest
// (":fire" → emoji/"fire"; ":" alone stays general; "::" → emoji/":").

// HeroPresentation.swift
public nonisolated enum HeroPresentation {
    /// Hero card shows only when the TOP-ranked result carries hero content;
    /// that result is removed from the table rows to avoid duplication.
    public static func split(_ ranked: [SearchResult]) -> (hero: SearchResult?, rows: [SearchResult])
}

// Ranker.defaultWeights additions: .urlClean: 112, .currency: 110, .translation: 110,
// .time: 108, .emoji: 45  (urlClean/currency/time above calculator's 100 — their
// parsers are disjoint from arithmetic, but a matched conversion must own the top slot).
```

- [ ] **Step 1: Failing tests** — `HeroTests.swift`:

```swift
import Testing
@testable import BopopKit

@Test func heroSplitTakesTopResultWithHero() {
    let hero = SearchResult(id: "x", providerID: .currency, title: "t",
        action: .copyText("v"),
        hero: HeroContent(left: "123 MYR", right: "$30.03"), sortHint: 0)
    let plain = SearchResult(id: "y", providerID: .apps, title: "Safari",
        action: .openApp("s"), sortHint: 0)
    let split = HeroPresentation.split([hero, plain])
    #expect(split.hero?.id == "x")
    #expect(split.rows.map(\.id) == ["y"])
}

@Test func heroSplitPassesThroughWhenTopHasNoHero() {
    let plain = SearchResult(id: "y", providerID: .apps, title: "Safari",
        action: .openApp("s"), sortHint: 0)
    let split = HeroPresentation.split([plain])
    #expect(split.hero == nil)
    #expect(split.rows.map(\.id) == ["y"])
}

@Test func calculatorResultCarriesHero() async throws {
    let results = try await CalculatorProvider().results(
        for: ParsedQuery(mode: .general, term: "123*456"))
    let hero = try #require(results.first?.hero)
    #expect(hero.left == "123*456")
    #expect(hero.right == "56,088")
    #expect(hero.rightBadge == "Fifty-Six Thousand Eighty-Eight")
}

@Test func queryParserEmojiPrefix() {
    #expect(QueryParser.parse(raw: ":fire", stickyMode: .general)
        == ParsedQuery(mode: .emoji, term: "fire"))
    #expect(QueryParser.parse(raw: ":", stickyMode: .general).mode == .general)
    #expect(QueryParser.parse(raw: "t hello", stickyMode: .general)
        == ParsedQuery(mode: .translation, term: "hello"))
}

@Test func escapeExitsNewModes() {
    #expect(EscapePolicy.action(textIsEmpty: true, stickyMode: .emoji) == .exitMode)
    #expect(EscapePolicy.action(textIsEmpty: true, stickyMode: .translation) == .exitMode)
}
```

- [ ] **Step 2:** `swift test --filter Hero` → FAIL (types missing).
- [ ] **Step 3:** Implement. Calculator hero: `left` = trimmed expression, `leftBadge` = operation name from the top-level operator (`*`/`×` "Product", `+` "Sum", `-`/`−` "Difference", `/`/`÷` "Quotient", `%` "Remainder", `^` "Power", mixed/none → nil); `right` = grouped format (extend `CalculatorFormatter` with `grouped(from:)` using `NumberFormatter` `.decimal`, `en_US_POSIX`, up to 10 fraction digits); `rightBadge` = `NumberFormatter` `.spellOut` capitalized per word, only for integer |value| < 1e9, else nil. Keep existing `title`/`action` untouched (existing tests must stay green).
- [ ] **Step 4:** `swift test` → all green (78 existing + new).
- [ ] **Step 5:** Commit `feat: add hero content plumbing, emoji/translation modes`.

Also in this task: `CommandsProvider` gains `cmd:emoji` "Emoji Picker…" (`icon: .symbol("face.smiling")`, keywords `["emoji", "picker"]`, `action: .enterMode(.emoji)`, sortHint 2) and `cmd:translate` "Translate…" (`icon: .symbol("character.bubble")`, keywords `["translate", "chinese", "english"]`, `action: .enterMode(.translation)`, sortHint 3). Assert both in the existing commands test.

---

### Task 2: Currency (Kit)

**Files:**
- Create: `Sources/BopopKit/Currency.swift`
- Modify: `Sources/BopopKit/Storage.swift` (add `public var ratesFileURL: URL` → `baseDirectory/"rates.json"`)
- Test: `Tests/BopopKitTests/CurrencyTests.swift`

**Interfaces:**
- Consumes: `HeroContent`, `ProviderID.currency`, `Storage.save/load`, `ResultProvider`.
- Produces (Task 7 wires): `CurrencyProvider(store:fetcher:now:)`, `LiveRateFetcher()`.

```swift
public nonisolated struct CurrencyQuery: Equatable, Sendable {
    public let amount: Double
    public let from: String   // ISO code, uppercased
    public let to: String
}
public nonisolated enum CurrencyParser {
    public static func parse(_ term: String) -> CurrencyQuery?
}
public protocol RateFetcher: Sendable {
    func fetchEURBaseRates() async throws -> [String: Double]
}
public final class LiveRateFetcher: RateFetcher { public init() {} }
public final class RateStore {          // wraps Storage, envelope version 1
    public init(storage: Storage)
    public func cached() -> CachedRates?          // nil if absent/corrupt
    public func save(rates: [String: Double], fetchedAt: Date)
}
public nonisolated struct CachedRates: Codable, Equatable, Sendable {
    public let rates: [String: Double]   // EUR-base, includes "EUR": 1.0
    public let fetchedAt: Date
    public func convert(_ query: CurrencyQuery) -> Double?   // cross via EUR
    public func isStale(now: Date) -> Bool                   // > 12 * 3600
}
public final class CurrencyProvider: ResultProvider {
    public let id: ProviderID = .currency
    public init(store: RateStore, fetcher: RateFetcher, now: @escaping @Sendable () -> Date = Date.init)
}
```

Parser grammar: optional leading symbol/code, amount (digits, one `.`, optional `,` thousands — strip commas), optional symbol/code after amount, separator `to`/`in` (case-insensitive, surrounded by spaces or none before target), target code/symbol. Accept: `123myr to usd`, `100 usd in myr`, `€45 to myr`, `myr 250 to sgd`, `$1,200 to sgd`. Reject: missing either side, unknown code, amount ≤ 0 or non-finite, same-currency no-op is VALID (rate 1). Symbol table: `$`→USD, `€`→EUR, `£`→GBP, `¥`→JPY, `₩`→KRW, `₹`→INR, `RM`→MYR (case-insensitive), `S$`→SGD, `HK$`→HKD, `NT$`→TWD, `฿`→THB, `₫`→VND, `Rp`→IDR, `₱`→PHP. Codes: validate against a static set of the ~40 ECB+common ISO codes (frankfurter coverage: AUD BGN BRL CAD CHF CNY CZK DKK EUR GBP HKD HUF IDR ILS INR ISK JPY KRW MXN MYR NOK NZD PHP PLN RON SEK SGD THB TRY USD ZAR).

Provider behavior (write tests for each): parse miss → `[]`. Fresh cache → one result, `hero.left = "123 MYR"` + `leftBadge` currency display name (`Locale(identifier: "en_US").localizedString(forCurrencyCode:)`), `hero.right` = target-formatted amount (symbol if in table, else `"30.03 USD"`; 2 fraction digits, grouped), `rightBadge` = target display name, `note` = relative age ("Updated 2 hours ago" via `RelativeDateTimeFormatter`, en_US) — nil if < 15 min old. `action: .copyText(<bare number, 2 decimals>)`, `keywords: [query.term]` (Ranker survival — same trick as calculator), `sortHint: 0`. Stale cache → return cached answer immediately AND fire fetch in a detached task that saves; do not block. No cache: fetch inline (engine already runs providers concurrently; 5 s cap); on failure return the single row `title: "Exchange rates unavailable — check connection"`, `icon: .symbol("wifi.slash")`, `action: .copyText("")`, no hero. `LiveRateFetcher`: `URLSession` ephemeral config, `timeoutIntervalForRequest = 5`, GET `https://api.frankfurter.dev/v1/latest?base=EUR`, decode `{ "rates": [String: Double] }`, insert `"EUR": 1.0`.

- [ ] Step 1: failing tests — parser table test (all accepts/rejects above), `convert` cross-rate math (`MYR→USD == amount / rates["MYR"] * rates["USD"]`), staleness boundary (11 h 59 m fresh, 12 h 1 m stale), corrupt `rates.json` → `cached() == nil` + `.corrupt` file exists (copy pattern from existing store tests), provider flow with a `MockRateFetcher` (records call count; fresh cache → 0 calls).
- [ ] Step 2: `swift test --filter Currency` → FAIL.
- [ ] Step 3: implement.
- [ ] Step 4: `swift test` → green.
- [ ] Step 5: Commit `feat: add currency conversion with cached ECB rates` (body: explain network-invariant amendment).

---

### Task 3: Time conversion (Kit)

**Files:**
- Create: `Sources/BopopKit/TimeConvert.swift`
- Test: `Tests/BopopKitTests/TimeConvertTests.swift`

**Interfaces:**
- Produces: `TimeProvider(now:localTimeZone:)`.

```swift
public nonisolated struct TimeConversion: Equatable, Sendable {
    public let sourceDescription: String  // "Monday, 13 October, 9:00 AM, GMT-4"
    public let localDescription: String   // "October 13, 2025 at 21:00"
    public let instant: Date
}
public nonisolated enum TimeQueryParser {
    public static func parse(_ term: String, now: Date, localZone: TimeZone) -> TimeConversion?
}
public final class TimeProvider: ResultProvider {
    public let id: ProviderID = .time
    public init(now: @escaping @Sendable () -> Date = Date.init,
                localTimeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current })
}
```

Zone token table (static, lowercased key → TimeZone identifier): abbreviations `est/edt/eastern`→America/New_York, `cst/cdt/central`→America/Chicago, `mst/mdt/mountain`→America/Denver, `pst/pdt/pacific`→America/Los_Angeles, `gmt/utc`→GMT, `bst`→Europe/London, `cet/cest`→Europe/Paris, `jst`→Asia/Tokyo, `kst`→Asia/Seoul, `ist`→Asia/Kolkata, `sgt`→Asia/Singapore, `hkt`→Asia/Hong_Kong, `aest/aedt`→Australia/Sydney, `myt`→Asia/Kuala_Lumpur; aliases `nyc`, `new york`, `sf`, `san francisco`→America/Los_Angeles, `la`, `london`, `paris`, `berlin`, `tokyo`, `seoul`, `sydney`, `singapore`, `hong kong`, `kl`, `kuala lumpur`, `taipei`, `shanghai`, `beijing`→Asia/Shanghai, `dubai`, `mumbai`, `delhi`; plus every `TimeZone.knownTimeZoneIdentifiers` last-path-component with `_`→space, lowercased.

Two shapes:
1. `time in <token>` / `<token> time` → the answer is the CURRENT time in that zone: hero left = place name capitalized (e.g. "Tokyo") with GMT-offset badge, hero right = current time formatted in that zone, rightBadge = zone identifier city. In this shape `localDescription` carries the remote-time string (it is what Return copies).
2. `<datetime phrase> <zone token>` (zone token must be a suffix; strip it, feed the rest to `NSDataDetector(types: .date)` with a `Calendar` whose timeZone = token's zone — set detector context by constructing dates via `DateComponents` re-interpretation: detect in local, then rebase components into source zone). Result: `instant` absolute; `sourceDescription` formatted in source zone (`EEEE, d MMMM, h:mm a` + ", GMT±H"), `localDescription` formatted local (`MMMM d, yyyy 'at' HH:mm`). Formatters `en_US_POSIX`.

Provider: parse miss → `[]`. Hit → hero (`left` = sourceDescription, `leftBadge` = source zone GMT offset string, `right` = localDescription, `rightBadge` = "Your Time"), `action: .copyText(localDescription)`, `keywords: [query.term]`, `sortHint: 0`.

- [ ] Step 1: failing tests with **fixed** `now` (e.g. `Date(timeIntervalSince1970: 1_760_000_000)`) and fixed local zone `Asia/Kuala_Lumpur`: `"9am eastern"` → 21:00 local same date (DST-aware: America/New_York in that epoch), `"oct 13 9pm PST"`, `"time in tokyo"`, `"tomorrow 3pm london"`, rejects: `"eastern"` alone with no time, `"hello world"`, `"9am"` (no zone → `[]`, calculator/apps own it).
- [ ] Step 2: `swift test --filter TimeConvert` → FAIL.
- [ ] Step 3: implement.
- [ ] Step 4: `swift test` → green.
- [ ] Step 5: Commit `feat: add timezone conversion provider`.

---

### Task 4: URL cleaner (Kit)

**Files:**
- Create: `Sources/BopopKit/URLClean.swift`
- Test: `Tests/BopopKitTests/URLCleanTests.swift`

**Interfaces:**
- Produces: `URLCleanProvider()`.

```swift
public nonisolated struct CleanedURL: Equatable, Sendable {
    public let original: String
    public let cleaned: String
    public let removedCount: Int
}
public nonisolated enum URLCleaner {
    public static func clean(_ raw: String) -> CleanedURL?  // nil: not http(s) URL w/ host
}
public final class URLCleanProvider: ResultProvider { public let id: ProviderID = .urlClean; public init() }
```

Rules: global exact-or-prefix param names — prefixes `utm_`, `vero_`, `oly_`, `pd_rd_`, `pf_rd_`; exact `fbclid gclid gclsrc dclid msclkid igshid igsh mc_eid mc_cid spm _hsenc _hsmi wickedid yclid twclid ttclid s_kwcid ref_src ref_url`. Per-host (host suffix match): `amazon.*` also removes exact `ref tag psc th linkCode linkId` and strips a path segment starting `/ref=`; `youtube.com`/`youtu.be` also removes `si pp feature`. `si` is NOT global (breaks other sites) — youtube/spotify (`open.spotify.com`) only. Keep survivor param order; keep fragment; lowercase nothing; preserve everything else byte-for-byte where possible (rebuild via `URLComponents`). Return nil if scheme not http/https or no host. If `removedCount == 0` → provider returns `[]` (no noise).

Provider: hero (`left` = original middle-truncated to 60 chars (`…`), `leftBadge` = "Original", `right` = cleaned (same truncation for display), `rightBadge` = "\(removedCount) tracker\(s) removed", note nil), `title` = cleaned, `action: .openURL(cleaned)`, `secondaryActions: [.copyText(cleaned)]`, `keywords: [query.term]`, `icon: .symbol("link")`, `sortHint: 0`.

- [ ] Step 1: failing tests: utm bundle removed; fbclid removed; amazon `/dp/B0X/ref=sr_1_1?tag=x&keywords=y` → path `/dp/B0X`, `tag` gone, `keywords` kept; youtube `?v=abc&si=xyz` → `si` gone `v` kept; `si` kept on non-youtube host; already-clean URL → provider `[]` but `URLCleaner.clean` returns removedCount 0; not-a-URL / `ftp://` → nil; survivor order preserved; fragment preserved.
- [ ] Step 2: `swift test --filter URLClean` → FAIL.
- [ ] Step 3: implement. Step 4: `swift test` green.
- [ ] Step 5: Commit `feat: add URL tracking-parameter cleaner`.

---

### Task 5: Emoji picker (Kit + data)

**Files:**
- Create: `Sources/BopopKit/Emoji.swift`, `Support/generate-emoji.swift` (generator script), `Sources/BopopKit/Resources/emoji.json`
- Modify: `Package.swift` (BopopKit target: `resources: [.copy("Resources/emoji.json")]`)
- Test: `Tests/BopopKitTests/EmojiTests.swift`

**Interfaces:**
- Produces: `EmojiProvider(catalog:frecencyFor:)`, `EmojiCatalog()`.

```swift
public nonisolated struct EmojiEntry: Codable, Equatable, Sendable {
    public let char: String       // "🔥"
    public let name: String       // "fire"
    public let keywords: [String] // ["flame", "hot", ...]
}
public final class EmojiCatalog {
    public init()                          // lazy-loads Bundle.module emoji.json once
    public var entries: [EmojiEntry] { get }
}
public final class EmojiProvider: ResultProvider {
    public let id: ProviderID = .emoji
    public init(catalog: EmojiCatalog, frecencyFor: @escaping @Sendable (String) -> Double)
}
```

Data generation (run once, commit output): `Support/generate-emoji.swift` fetches `https://unicode.org/Public/emoji/latest/emoji-test.txt` (fully-qualified entries only, skip skin-tone/component lines) and CLDR keywords from `https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json`; joins on emoji char; name = CLDR tts (fallback: emoji-test description); writes compact JSON array. If network is unavailable at generation time, fallback: derive from `Unicode.Scalar.properties` (`isEmojiPresentation` singles) with `properties.name` lowercased as name, empty keywords — but PREFER the CLDR path. Target ≈1,900 entries, no skin-tone variants. Sanity-assert in the script: count > 1500, contains 🔥 with keyword "flame" (CLDR path).

Provider: mode `.emoji` only. Empty term → top 24 by frecency, ties in catalog order. Non-empty → all entries; Ranker filters/sorts. Result shape: `title = "\(entry.char)  \(entry.name)"` (emoji leads the row visually — no new IconRef case, row view untouched) and `keywords: [entry.name] + entry.keywords` — the bare-name keyword is REQUIRED because the emoji char at the start of the title breaks Ranker's exact/prefix tiers, and `bestTier` takes the max over title+keywords. `id` = the emoji char itself (frecency key). `icon: .none`. `action: .copyText(entry.char)`, `sortHint` = catalog index.

- [ ] Step 1: failing tests: catalog loads (count > 1500; contains char "🔥" named "fire"); provider empty term returns 24; frecency lifts a recorded emoji to front; search "fir" ranks fire first (run through `Ranker.rank` with `defaultWeights` like engine does); Return action copies the char.
- [ ] Step 2: FAIL. Step 3: run generator (`swift Support/generate-emoji.swift > Sources/BopopKit/Resources/emoji.json`), implement catalog/provider. Step 4: `swift test` green.
- [ ] Step 5: Commit `feat: add emoji picker with CLDR keyword search`.

---

### Task 6: Translation logic (Kit, engine-agnostic)

**Files:**
- Create: `Sources/BopopKit/Translate.swift`
- Test: `Tests/BopopKitTests/TranslateTests.swift`

**Interfaces:**
- Produces (Task 8 implements `Translator` with Apple framework and wires):

```swift
public nonisolated enum TranslationTarget: String, Sendable, Equatable {
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case chineseTraditional = "zh-Hant"
}
public nonisolated enum TranslationDirection {
    /// Han chars present → .english, else → chineseVariant
    public static func target(for text: String, chineseVariant: TranslationTarget) -> TranslationTarget
}
public nonisolated enum TranslatorAvailability: Sendable, Equatable {
    case ready, needsDownload, unsupported
}
public protocol Translator: Sendable {
    func availability(target: TranslationTarget) async -> TranslatorAvailability
    func translate(_ text: String, to target: TranslationTarget) async throws -> String
    func requestDownload(target: TranslationTarget) async
}
public final class TranslationProvider: ResultProvider {
    public let id: ProviderID = .translation
    public init(translator: Translator,
                chineseVariant: @escaping @Sendable () -> TranslationTarget,
                debounceNanoseconds: UInt64 = 300_000_000)
}
```

Han detection: any scalar in ranges 0x4E00–0x9FFF, 0x3400–0x4DBF, 0xF900–0xFAFF. Provider (mode `.translation` only): empty term → `[]`. `needsDownload` → single row `title: "Download Chinese ⇄ English translation…"`, `icon: .symbol("arrow.down.circle")`, `action: .copyText("")` — Task 8 swaps the action to a real download trigger via a new `ResultAction` case? NO new case: Task 8's `AppleTranslator.requestDownload` is invoked by the provider itself when that row is EXECUTED — but ActionRunner only sees ResultAction. Resolution: provider gives the download row `action: .enterMode(.translation)` (harmless no-op re-entry) and Task 8's AppleTranslator calls `requestDownload` lazily inside `translate` when needed; the row is informational. Keep it that simple. `unsupported` → row "Translation not available on this Mac". `ready` → `try? await Task.sleep(nanoseconds: debounce)` then translate (cancellation propagates — engine cancels stale generations, same pattern as file search); result hero: `left` = source text, `leftBadge` = "Chinese"/"English" (detected source), `right` = translation, `rightBadge` = target ("English" / "Simplified Chinese" / "Traditional Chinese"), `action: .copyText(translation)`, `keywords: [query.term]`, `sortHint: 0`. Translate failure → `[]`. Debounce 0 in tests.

- [ ] Step 1: failing tests with `MockTranslator` (scripted availability + echo translation + call recorder): direction detection (pure ASCII → variant; "你好" → english; mixed "hello 你好" → english); ready flow produces hero + copy action; needsDownload row; unsupported row; empty term; debounce cancellation (start query, cancel task, translator never called — mirror existing `queryEngineCancellationStopsPublish` style).
- [ ] Step 2: FAIL. Step 3: implement. Step 4: green.
- [ ] Step 5: Commit `feat: add translation provider logic with engine seam`.

---

### Task 7: Hero card UI + wiring local providers (app target)

**Files:**
- Create: `Sources/Bopop/PaletteHeroView.swift`
- Modify: `Sources/Bopop/PaletteLayout.swift`, `Sources/Bopop/PaletteController.swift`, `Sources/Bopop/PaletteMetrics.swift`, `Sources/Bopop/ActionRunner.swift`, `Sources/Bopop/AppDelegate.swift`
- Test: manual QA via `BOPOP_DEBUG_AUTOSHOW` + `screencapture` (see HANDOVER toolkit)

**Interfaces:**
- Consumes: `HeroPresentation.split`, `HeroContent`, `CurrencyProvider`, `TimeProvider`, `URLCleanProvider`, `EmojiProvider`, `ResultAction.openURL`.

Work:
1. `PaletteHeroView: NSView` — horizontal split: left pane (input text 22 pt monospaced medium, white 0.92; badge = rounded-rect chip, 11 pt, white 0.55 on white 0.08 fill), center column (→ glyph 20 pt white 0.55; note 10 pt white 0.35 under it), right pane mirrored. Vertical hairline separators (white 0.07) between panes, matching Raycast reference. Card background white 0.04, corner radius 10 via layer (this is an opaque-ish sublayer INSIDE the already-masked panel — plain `cornerRadius` is fine here; the `maskImage` gotcha applies to the panel's visual-effect view only). Height: `PaletteMetrics.heroHeight = 96`. Text fields non-editable, single line, truncating middle.
2. `PaletteController`: after ranking, run `HeroPresentation.split`; if hero present, show/layout hero view and feed table `rows` only; Return/⌘C with hero visible and table selection at none/first → execute the hero result. Selection sync must respect the row-init guard (gotcha #4 — don't touch `PaletteRowView` internals). Footer verb: `openURL` → "open".
3. `ActionRunner`: handle `case .openURL(let s)`: `guard let url = URL(string: s), url.scheme == "http" || url.scheme == "https" else { return }`, `NSWorkspace.shared.open(url)`, close palette (same path as openApp/openFile).
4. `AppDelegate`: wire into `.general`: `CurrencyProvider(store: RateStore(storage: storage), fetcher: LiveRateFetcher())`, `TimeProvider()`, `URLCleanProvider()`; new `.emoji: [EmojiProvider(catalog: EmojiCatalog(), frecencyFor: usageStore.score)]`.

- [ ] Steps: build (`make app`), autoshow, type `123*456` → screencapture → verify card (Read the png); type a tracked URL → verify card + "open" verb; `:fire` → emoji rows; `swift test` still green; commit `feat: render hero answer card, wire currency/time/url/emoji providers`.

---

### Task 8: Apple translation host + settings (app target)

**Files:**
- Create: `Sources/Bopop/AppleTranslator.swift`
- Modify: `Sources/Bopop/AppDelegate.swift`, `Sources/Bopop/SettingsModel.swift`, `Sources/Bopop/SettingsView.swift`

**Interfaces:**
- Consumes: `Translator`, `TranslationTarget`, `TranslationProvider`.

Work:
1. `AppleTranslator: Translator` — `import Translation`. Availability via `LanguageAvailability().status(from:to:)` (`.installed`→ready, `.supported`→needsDownload, `.unsupported`→unsupported). Session: hidden 1×1 `NSHostingView` (added to a persistent offscreen window) hosting a SwiftUI view with `.translationTask(configuration)` — requests flow through an `AsyncStream` bridge: `translate()` enqueues (text, target, continuation); the task closure drains the queue with `session.translate(_:)`. Rebuild `TranslationSession.Configuration` (set `.invalidate()` or assign new config) when target pair changes. `requestDownload` → `session.prepareTranslation()` inside the task closure (triggers the system download sheet).
2. `SettingsModel`: `var chineseVariant: TranslationTarget` persisted in defaults key `"chineseVariant"` (raw string, default `zh-Hans`), same pattern as `storedClipboardLimit`. `SettingsView`: Picker "Chinese variant" (Simplified / Traditional) in the existing form.
3. `AppDelegate`: `.translation: [TranslationProvider(translator: appleTranslator, chineseVariant: { settingsModel.chineseVariant })]` — note init-order: settingsModel is built AFTER engine today; hoist the defaults read (`SettingsModel.storedChineseVariant(in: defaults)`) so the closure reads defaults directly, avoiding the ordering trap.

- [ ] Steps: build, manual QA (`t hello` → 你好 card after model download; `t 你好` → hello), `swift test` green, commit `feat: wire Apple on-device translation with variant setting`.

---

### Task 9: Menu-bar removal → footer gear (app target)

**Files:**
- Modify: `Sources/Bopop/AppDelegate.swift` (delete statusItem + its menu; add `applicationShouldHandleReopen`), `Sources/Bopop/PaletteFooterView.swift` (gear button), `Sources/Bopop/PaletteController.swift` (menu action plumbing)

Work:
1. Delete `statusItem` property and the whole menu block in `applicationDidFinishLaunching`. Keep `showSettings`/`openScriptsFolder`/`quitBopop` selectors.
2. `func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { paletteController.show(); return false }` — the hotkey-failure failsafe. (Check PaletteController for the show/toggle method name; add `show()` if only `toggle()` exists.)
3. `PaletteFooterView`: gear button (`NSButton`, `gearshape` symbol, borderless, white 0.45→0.8 on hover) appended to `rightCluster` — stack uses `setViews(in: .leading)` today, order [navigate, copy, primary, gear] is fine within the trailing-pinned cluster. Button pops `NSMenu` (Settings…, Open Scripts Folder, ─, Quit Bopop) via `menu.popUp(positioning:at:in:)`. Callbacks via closure properties set by PaletteController → AppDelegate (follow existing callback style, e.g. `onWillShow`).
4. README/HANDOVER note: recover a broken hotkey by relaunching Bopop (reopen shows palette).

- [ ] Steps: build, QA (gear menu opens Settings, quits; `open -a Bopop` while running shows palette; hotkey still works), `swift test` green, commit `feat: replace menu-bar item with palette footer menu`.

---

### Task 10: Docs + final verification

**Files:**
- Modify: `README.md`, `HANDOVER.md`, `PRODUCT.md`, `DESIGN.md`

Work: README — new features list entries, security section: amend network invariant (exchange rates only, on-demand, frankfurter.dev), test count refresh, remove menu-bar paragraph → footer gear + reopen failsafe. HANDOVER — invariants amendment, new gotchas discovered during Tasks 7–9, storage surface (`rates.json`, `chineseVariant` default). PRODUCT/DESIGN — feature list + hero card spec.

- [ ] Steps: `make test` full output captured, `make app` builds, docs updated, commit `docs: document v2 features and amended network invariant`.

---

## Execution notes (orchestrator)

- Task 1 first, alone. Then Tasks 2–6 in parallel (Sonnet agents, disjoint files — same worktree is safe; Package.swift only in Task 5, Storage.swift only in Task 2). Then 7 → 8 → 9 sequential (shared app-target files). Then 10.
- Each agent: read spec + this plan's task + the named existing files; TDD; commit only its own files; report diff summary + test output. Fable reviews every diff before the next wave.
