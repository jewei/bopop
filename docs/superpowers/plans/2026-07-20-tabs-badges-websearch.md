# Tabs, Badges, Web Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pill tab row (unified with modes), per-row category badges, always-last web-search row with configurable engine — per `docs/superpowers/specs/2026-07-20-tabs-badges-websearch-design.md`.

**Architecture:** Task 1 lands all Kit changes (Mode.apps, SearchEngine, WebSearchProvider, Ranker pin-last rule, CategoryBadge). Tasks 2 and 3 are app-target and file-disjoint (2: tabs UI in PaletteTabsView/PaletteController/PaletteLayout/PaletteMetrics; 3: row badge + settings + wiring in ResultRowView/SettingsModel/SettingsView/AppDelegate) — safe in parallel. Task 4: docs + QA.

**Tech Stack:** Swift 6.2, SPM, swift-testing. Baseline `c610e98`, 151 tests.

## Global Constraints

Same as the v2 plan (docs/superpowers/plans/2026-07-19-bopop-v2-features.md): Kit = Foundation+os only; MainActor default isolation; no new network (search URLs open in the browser — Bopop itself never fetches them); no content logging; TDD; full `swift test` green before every commit; Conventional Commits; UI follows DESIGN.md Minimal Mono and HANDOVER gotchas #4/#5/#6.

---

### Task 1: Kit — Mode.apps, SearchEngine, WebSearchProvider, Ranker rule, CategoryBadge

**Files:**
- Modify: `Sources/BopopKit/Query.swift` (Mode.apps), `Sources/BopopKit/Result.swift` (ProviderID.webSearch), `Sources/BopopKit/Apps.swift` (serve .apps mode), `Sources/BopopKit/Ranker.swift` (pin-last rule)
- Create: `Sources/BopopKit/WebSearch.swift` (SearchEngine + WebSearchProvider), `Sources/BopopKit/CategoryBadge.swift`
- Test: `Tests/BopopKitTests/WebSearchTests.swift`, extend Hero/Ranker tests as needed

**Interfaces (Produces — Tasks 2/3 depend on exact names):**

```swift
public nonisolated enum Mode: String { /* + */ case apps }

public nonisolated enum SearchEngine: String, CaseIterable, Sendable {
    case google, duckDuckGo, bing, brave
    public var displayName: String   // "Google", "DuckDuckGo", "Bing", "Brave"
    public func searchURL(for term: String) -> URL?
    // google: https://www.google.com/search?q=
    // duckDuckGo: https://duckduckgo.com/?q=
    // bing: https://www.bing.com/search?q=
    // brave: https://search.brave.com/search?q=
    // Percent-encode with .urlQueryAllowed minus "&+?=#".
}

public final class WebSearchProvider: ResultProvider {
    public let id: ProviderID = .webSearch
    public init(engine: @escaping @Sendable () -> SearchEngine)
    // .general mode + non-empty trimmed term → exactly one result:
    // id "websearch", title: "Search \(engine.displayName) for \"\(term)\"",
    // icon .symbol("magnifyingglass"), badge "Web", keywords [query.term],
    // action .openURL(url.absoluteString), sortHint 0. Otherwise [].
}

public nonisolated enum CategoryBadge {
    public static func text(for result: SearchResult) -> String?
    // result.badge if non-nil; else providerID: .apps "Apps", .files "Files",
    // .clipboard "Clipboard", .emoji "Emoji", .webSearch "Web"; else nil.
}

// Ranker.rank: results with providerID == .webSearch are NEVER filtered by tier
// and ALWAYS sort after every non-webSearch result (stable order among themselves).
```

`AppsProvider.results`: change the mode guard from `== .general` to `.general || .apps` (empty-term frecency list + full-catalog search work identically in both).

- [ ] Failing tests first: engine URL table (plain term, "swift 6 concurrency" spaces, "蘋果" CJK, "a&b=c#d" reserved chars — assert exact encoded absoluteString per engine); provider row shape + empty/whitespace term → []; wrong mode → []; Ranker: webSearch row survives a query it doesn't tier-match AND sorts last against a higher-scoring app result; CategoryBadge table incl. explicit-badge passthrough (scripts "Script") and nil cases; EscapePolicy .apps → exitMode; AppsProvider serves .apps.
- [ ] `swift test --filter WebSearch` FAIL → implement → full `swift test` green (151 + new).
- [ ] Commit: `feat: add apps mode, web-search provider, category badges (kit)`.

---

### Task 2: Tab row UI (app target)

**Files:**
- Create: `Sources/Bopop/PaletteTabsView.swift`
- Modify: `Sources/Bopop/PaletteController.swift`, `Sources/Bopop/PaletteLayout.swift`, `Sources/Bopop/PaletteMetrics.swift`

**Interfaces:**
- Consumes: `Mode` (incl. `.apps`), existing `layoutConstraints` toggle pattern (see scrollTopToHero), `PaletteModeChipView` (to REMOVE), `enterMode(_:)` / `stickyMode` in PaletteController.
- Produces: `PaletteTabsView` with `var onSelect: ((Mode) -> Void)?`, `func setActive(_ mode: Mode)`, static ordered list `[(Mode, String)]`: (.general "All"), (.apps "Apps"), (.fileSearch "Files"), (.clipboard "Clipboard"), (.emoji "Emoji"), (.translation "Translate").

Work:
1. `PaletteTabsView`: horizontal NSStackView of pill NSButtons (borderless, monospaced 11pt medium). Active: `BrandColor` accent at ~0.25 alpha fill, text white 0.92; inactive: clear fill, text white 0.45, hover white 0.7 (tracking areas like PaletteFooterGearButton). Corner radius 999 (capsule via height/2). Row height `PaletteMetrics.tabsHeight = 34`, pills inset leading `PaletteMetrics.footerInset`, leading-aligned.
2. `PaletteLayout`: tabs row sits directly under the field hairline; hero/scroll top anchors now hang off the tabs row's bottom (rework the scrollTopToSeparator/scrollTopToHero pair to anchor to tabsView.bottomAnchor; tabs row is ALWAYS visible, so this is a constant re-anchor, not a new toggle).
3. `PaletteController`: delete modeChip + its layout constraints and all `modeChip.*` lines (the generalFieldLeading/modeFieldLeading toggle collapses to the general constraint always active — field no longer shifts). Single sync point: everywhere `stickyMode` changes (enterMode, reset, Esc exitMode, apply of enterMode action, prefix-driven mode from QueryParser via the parsed query in `apply`) call `tabsView.setActive(...)`. NOTE: prefix modes (`f `/`:`/`t `) do NOT set stickyMode today — the parsed query's mode drives providers while stickyMode stays general until the command/Enter path sets it. Tabs must reflect the EFFECTIVE mode: track `lastParsedMode` from the latest engine update and highlight that. Read the current flow in PaletteController before coding; keep behavior, only add the highlight sync + panel height + tab clicks (tab click = enterMode, same as command rows).
4. ⇥/⇧⇥: in `control(_:textView:doCommandBySelector:)` handle `insertTab:`/`insertBacktab:` → cycle through the ordered tab list from the current effective mode → enterMode(next). Return true (consume).
5. `panelHeight` adds `PaletteMetrics.tabsHeight`.

Verification: `swift test` green; `make app`; BOPOP_DEBUG_AUTOSHOW QA — screenshot: tabs visible under field, All active; `f ` highlights Files; Esc returns to All; click Apps → apps-only results. Kill app.
- [ ] Commit: `feat: add pill tab row unified with modes`.

---

### Task 3: Row badges + engine setting + wiring (app target)

**Files:**
- Modify: `Sources/Bopop/ResultRowView.swift`, `Sources/Bopop/SettingsModel.swift`, `Sources/Bopop/SettingsView.swift`, `Sources/Bopop/AppDelegate.swift`

Work:
1. `ResultRowView`: wherever it currently reads `result.badge`, read `CategoryBadge.text(for: result)` instead. No layout change (badge pipeline exists; HANDOVER gotcha #6 — badge stays in the trailing gravity area).
2. `SettingsModel`: `storedSearchEngine(in:)` static reader (defaults key `"searchEngine"`, raw string, default `.google`) + instance property, mirroring `storedChineseVariant`. `SettingsView`: "Search engine" Picker with the four `displayName`s, matching the existing form style.
3. `AppDelegate`: `.general` gains `WebSearchProvider(engine: { MainActor.assumeIsolated { SettingsModel.storedSearchEngine(in: .standard) } })` (same bridge pattern as chineseVariantFor); new `.apps: [appsProvider]` provider-map entry.

Verification: `swift test` green; `make app`; QA — type `apple`: apps list shows "Apps" badges and last row reads `Search Google for "apple"` with "Web" badge; Return on it opens the browser; switch engine to DuckDuckGo in Settings and confirm the row title updates on next query. Kill app.
- [ ] Commit: `feat: add category badges, web-search row wiring, engine setting`.

---

### Task 4: Docs + final QA

README (features + tabs + web search + settings surface), HANDOVER (tab/mode unification note, ⇥ now spent, storage key `searchEngine`, test count), PRODUCT.md, DESIGN.md (tab row spec). Full `make test` + `make app`. Commit `docs: document tabs, badges, and web search`.

---

## Execution notes (orchestrator)

Task 1 alone → Tasks 2 ∥ 3 (file-disjoint) → Task 4. Sonnet implementers, Fable reviews each diff.
