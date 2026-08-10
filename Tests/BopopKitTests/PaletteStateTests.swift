import Foundation
import Testing
@testable import BopopKit

// Composition tests for the palette's state.
//
// The six modules this one replaces were each unit-tested in isolation while
// the sequencing that composed them lived in an untested 1155-line controller.
// Everything here drives whole sequences — type, publish, arrow, publish — and
// asserts on the returned plans.

@MainActor
private func state(
    orderedModes: [Mode] = [.general, .apps, .fileSearch, .clipboard, .emoji, .translation],
    gridColumns: Int = 10
) -> PaletteState {
    PaletteState(
        configuration: PaletteStateConfiguration(
            orderedModes: orderedModes,
            gridColumns: gridColumns
        )
    )
}

private nonisolated func row(
    _ id: String,
    title: String? = nil,
    hero: HeroContent? = nil
) -> SearchResult {
    SearchResult(
        id: id,
        providerID: .apps,
        title: title ?? id,
        action: .copyText(id),
        hero: hero,
        sortHint: 0
    )
}

private nonisolated func heroContent(autocomplete: String? = nil) -> HeroContent {
    HeroContent(
        left: "1+1",
        leftBadge: nil,
        right: "2",
        rightBadge: nil,
        note: nil,
        autocompleteText: autocomplete
    )
}

@MainActor
private func update(
    _ query: ParsedQuery,
    _ results: [SearchResult],
    isFinal: Bool = true,
    generation: Int = 1
) -> QueryEngine.Update {
    QueryEngine.Update(
        query: query,
        results: results,
        generation: generation,
        isFinal: isFinal
    )
}

// MARK: - Query and parsing

@MainActor
@Test
func typingParsesOnceAndAsksTheEngineForThatExactQuery() {
    let palette = state()

    let plan = palette.setQueryText("f report")

    #expect(plan.query == ParsedQuery(mode: .fileSearch, term: "report"))
    #expect(plan.effects == [.runQuery(ParsedQuery(mode: .fileSearch, term: "report"))])
    // The engine is handed the same value the plan reports, so nothing
    // downstream can re-derive a different one.
    #expect(plan.presentation == .list)
}

/// `QueryParser` trims in every mode, and there is now exactly one parse, so a
/// trailing space cannot desync what was drawn from what was searched.
@MainActor
@Test
func trailingSpaceIsTrimmedOnceForBothTheEngineAndThePlan() {
    let palette = state()
    palette.enterMode(.apps)

    let plan = palette.setQueryText("safari ")

    #expect(plan.query.term == "safari")
    #expect(plan.effects == [.runQuery(ParsedQuery(mode: .apps, term: "safari"))])
}

/// Typing `:` used to flip the presentation to grid while the previous mode's
/// rows were still loaded, so the panel resized to grid metrics around table
/// rows for one frame.
@MainActor
@Test
func switchingModeMidTypingDropsThePreviousModesRows() {
    let palette = state()
    palette.setQueryText("saf")
    palette.apply(update(ParsedQuery(mode: .general, term: "saf"), [row("a"), row("b")]))

    // `:` alone is still general mode — the emoji prefix needs a character
    // after it — so this types the first one that actually switches.
    let plan = palette.setQueryText(":f")

    #expect(plan.presentation == .grid)
    #expect(plan.rows.isEmpty, "grid presentation must never be drawn over list rows")
    #expect(plan.focus == .none)
    #expect(plan.contentChanged)
}

@MainActor
@Test
func typingWithinOneModeKeepsTheRowsUntilTheNextPublication() {
    let palette = state()
    palette.setQueryText("saf")
    palette.apply(update(ParsedQuery(mode: .general, term: "saf"), [row("a")]))

    let plan = palette.setQueryText("safa")

    #expect(plan.rows.map(\.id) == ["a"], "no blank frame while the next query runs")
    #expect(!plan.contentChanged)
}

// MARK: - Applying engine updates

@MainActor
@Test
func anUpdateAnsweringADifferentQueryIsIgnored() {
    let palette = state()
    palette.setQueryText("current")

    let plan = palette.apply(
        update(ParsedQuery(mode: .general, term: "stale"), [row("ghost")])
    )

    #expect(plan.rows.isEmpty)
    #expect(plan.focus == .none)
}

@MainActor
@Test
func aHeroTakesFocusAndIsSplitOffTheRows() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "1+1")
    palette.setQueryText("1+1")

    let plan = palette.apply(
        update(query, [row("calc", hero: heroContent()), row("a"), row("b")])
    )

    #expect(plan.hero?.id == "calc")
    #expect(plan.rows.map(\.id) == ["a", "b"])
    #expect(plan.focus == .hero)
    #expect(plan.focusedResult?.id == "calc")
}

@MainActor
@Test
func withoutAHeroFocusStartsAtTheFirstRow() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")

    let plan = palette.apply(update(query, [row("a"), row("b")]))

    #expect(plan.hero == nil)
    #expect(plan.focus == .row(0))
    #expect(plan.focusedResult?.id == "a")
}

@MainActor
@Test
func noResultsMeansNoFocusAtAll() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "zzz")
    palette.setQueryText("zzz")

    let plan = palette.apply(update(query, []))

    #expect(plan.focus == .none)
    #expect(plan.focusedResult == nil)
}

/// CLAUDE.md: `apply` resets selection to row 0 on each update unless a
/// stay-open mutation named a row to restore. Previously only the arithmetic
/// was tested; the sequence that actually carries restoration across an
/// interim update was not.
@MainActor
@Test
func restorationSurvivesInterimUpdatesAndIsSpentOnTheFinalOne() {
    let palette = state()
    let query = ParsedQuery(mode: .clipboard, term: "")
    palette.enterMode(.clipboard)
    palette.apply(update(query, [row("one"), row("two"), row("three")]))
    palette.selectRow(2)
    #expect(palette.focusedResult?.id == "three")

    // Pin "three": the refresh remembers it, and it moves to the pinned block.
    palette.refreshPreservingSelection()

    // An interim update that does not contain it yet must not snap to row 0
    // and must keep the restoration alive.
    let interim = palette.apply(
        update(query, [row("one"), row("two")], isFinal: false)
    )
    #expect(interim.focus == .row(0))

    let final = palette.apply(
        update(query, [row("three"), row("one"), row("two")])
    )
    #expect(final.focus == .row(0))
    #expect(final.focusedResult?.id == "three", "⏎ still points at the pinned row")

    // Spent: the next ordinary update starts from row 0 again.
    let next = palette.apply(update(query, [row("one"), row("three")]))
    #expect(next.focusedResult?.id == "one")
}

@MainActor
@Test
func identicalSuccessiveUpdatesReportNoContentChange() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    let results = [row("a"), row("b")]

    let first = palette.apply(update(query, results, isFinal: false))
    let second = palette.apply(update(query, results))

    #expect(first.contentChanged)
    #expect(!second.contentChanged, "a settle publish and its final must not redraw twice")
}

@MainActor
@Test
func aRowChangingItsTitleCountsAsChangedContent() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    palette.apply(update(query, [row("a", title: "One")], isFinal: false))

    let plan = palette.apply(update(query, [row("a", title: "Renamed")]))

    #expect(plan.contentChanged, "same id, different text — the row must redraw")
}

// MARK: - List selection

@MainActor
@Test
func arrowsWalkTheListAndStopAtBothEnds() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    palette.apply(update(query, [row("a"), row("b")]))

    #expect(palette.moveSelection(.down).focus == .row(1))
    #expect(palette.moveSelection(.down).focus == .row(1), "clamps at the last row")
    #expect(palette.moveSelection(.up).focus == .row(0))
    #expect(palette.moveSelection(.up).focus == .row(0), "no hero, so row 0 is the top")
}

@MainActor
@Test
func upFromTheFirstRowReachesTheHeroCard() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "1+1")
    palette.setQueryText("1+1")
    palette.apply(update(query, [row("calc", hero: heroContent()), row("a")]))

    #expect(palette.moveSelection(.down).focus == .row(0))
    #expect(palette.moveSelection(.up).focus == .hero)
    #expect(palette.moveSelection(.up).focus == .hero, "the hero is the top")
}

@MainActor
@Test
func horizontalArrowsInListModeLeaveFocusToTheCaret() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    palette.apply(update(query, [row("a"), row("b")]))
    palette.moveSelection(.down)

    #expect(palette.moveSelection(.left).focus == .row(1))
    #expect(palette.moveSelection(.right).focus == .row(1))
}

@MainActor
@Test
func arrowsOnAnEmptyListDoNothing() {
    let palette = state()
    palette.setQueryText("zzz")
    palette.apply(update(ParsedQuery(mode: .general, term: "zzz"), []))

    #expect(palette.moveSelection(.down).focus == .none)
    #expect(palette.moveSelection(.up).focus == .none)
}

// MARK: - Grid selection

/// 24 tiles at 10 columns: rows of 10, 10, and a partial 4.
@MainActor
private func gridPalette() -> PaletteState {
    let palette = state()
    palette.enterMode(.emoji)
    palette.apply(
        update(
            ParsedQuery(mode: .emoji, term: ""),
            (0..<24).map { row("tile\($0)") }
        )
    )
    return palette
}

@MainActor
@Test
func gridMovesAreRowMajor() {
    let palette = gridPalette()

    #expect(palette.moveSelection(.right).focus == .row(1))
    #expect(palette.moveSelection(.down).focus == .row(11))
    #expect(palette.moveSelection(.up).focus == .row(1))
    #expect(palette.moveSelection(.left).focus == .row(0))
}

/// The old helper took a `columns` parameter and never read it, so ← from the
/// first tile of a row wrapped onto the end of the previous row.
@MainActor
@Test
func gridHorizontalMovesDoNotCrossRows() {
    let palette = gridPalette()
    palette.selectRow(10)

    #expect(palette.moveSelection(.left).focus == .row(10), "column 0 stays put")

    palette.selectRow(9)
    #expect(palette.moveSelection(.right).focus == .row(9), "last column stays put")
}

@MainActor
@Test
func gridUpFromTheFirstRowStaysPut() {
    let palette = gridPalette()
    palette.selectRow(3)

    #expect(palette.moveSelection(.up).focus == .row(3))
}

@MainActor
@Test
func gridDownIntoAPartialLastRowSnapsToTheLastTile() {
    let palette = gridPalette()
    palette.selectRow(17)

    // Column 7 does not exist in the 4-tile last row, so it lands on tile 23.
    #expect(palette.moveSelection(.down).focus == .row(23))
}

@MainActor
@Test
func gridMovesOnAnEmptyGridDoNothing() {
    let palette = state()
    palette.enterMode(.emoji)
    palette.apply(update(ParsedQuery(mode: .emoji, term: ""), []))

    // Neither of the two contradictory old answers — index 0 or a preserved
    // stale index — is representable: an empty grid has no focus.
    #expect(palette.moveSelection(.down).focus == .none)
    #expect(palette.moveSelection(.right).focus == .none)
}

// MARK: - Clicks

@MainActor
@Test
func clickingARowMovesFocusThere() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    palette.apply(update(query, [row("a"), row("b"), row("c")]))

    #expect(palette.selectRow(2).focusedResult?.id == "c")
}

@MainActor
@Test
func clickingOutOfRangeIsIgnored() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "x")
    palette.setQueryText("x")
    palette.apply(update(query, [row("a")]))

    #expect(palette.selectRow(7).focus == .row(0))
}

// MARK: - Escape

@MainActor
@Test
func escapeClearsTheTextFirst() {
    let palette = state()
    palette.setQueryText("safari")

    let plan = palette.escape()

    #expect(plan.queryText.isEmpty)
    #expect(plan.queryFieldText == "", "the adapter must write the cleared text back")
    #expect(plan.effects == [.runQuery(ParsedQuery(mode: .general, term: ""))])
}

@MainActor
@Test
func escapeThenLeavesAStickyMode() {
    let palette = state()
    palette.enterMode(.clipboard)

    let plan = palette.escape()

    #expect(plan.query.mode == .general)
    #expect(plan.effects == [.runQuery(ParsedQuery(mode: .general, term: ""))])
}

@MainActor
@Test
func escapeFinallyClosesThePalette() {
    let palette = state()

    #expect(palette.escape().effects == [.closePalette])
}

/// Every sticky mode is a mode ⎋ has to leave before it closes anything —
/// including transient ones like snippets that have no resting tab pill.
/// These assertions used to be spread across QueryTests, HeroTests and
/// SnippetsTests, one mode at a time.
@MainActor
@Test(arguments: [Mode.apps, .fileSearch, .clipboard, .emoji, .translation, .snippets])
func escapeLeavesEveryStickyModeBeforeClosing(mode: Mode) {
    let palette = state()
    palette.enterMode(mode)

    let left = palette.escape()
    #expect(left.query.mode == .general)
    #expect(left.effects == [.runQuery(ParsedQuery(mode: .general, term: ""))])

    #expect(palette.escape().effects == [.closePalette])
}

/// Text is cleared before the mode is left, in every mode.
@MainActor
@Test(arguments: [Mode.general, .apps, .fileSearch, .clipboard, .emoji, .translation])
func escapeClearsTextBeforeTouchingTheMode(mode: Mode) {
    let palette = state()
    palette.enterMode(mode)
    palette.setQueryText("text")

    let cleared = palette.escape()
    #expect(cleared.queryText.isEmpty)
    #expect(cleared.query.mode == mode, "the mode survives the first escape")
}

// MARK: - Tab

@MainActor
@Test
func tabCyclesTheTabRowFromTheEffectiveMode() {
    let palette = state(orderedModes: [.general, .apps, .fileSearch])

    #expect(palette.tab(shift: false).query.mode == .apps)
    #expect(palette.tab(shift: false).query.mode == .fileSearch)
    #expect(palette.tab(shift: false).query.mode == .general, "wraps around")
    #expect(palette.tab(shift: true).query.mode == .fileSearch, "and backwards")
}

/// Cycling continues from a prefix-typed mode, not just the sticky one.
@MainActor
@Test
func tabCyclesFromAPrefixTypedMode() {
    let palette = state(orderedModes: [.general, .apps, .fileSearch, .clipboard])
    palette.setQueryText("f report")

    #expect(palette.tab(shift: false).query.mode == .clipboard)
}

/// A mode with no resting pill has no slot to cycle from, so both directions
/// land on the first ordered mode rather than overshooting from an assumed 0.
@MainActor
@Test
func tabFromATransientModeLandsOnTheFirstOrderedMode() {
    let palette = state(orderedModes: [.general, .apps, .fileSearch])
    palette.enterMode(.snippets)

    #expect(palette.tab(shift: false).query.mode == .general)
}

@MainActor
@Test
func tabAutocompletesAHeroThatOptsIn() {
    let palette = state()
    let query = ParsedQuery(mode: .general, term: "1+1")
    palette.setQueryText("1+1")
    palette.apply(update(query, [row("calc", hero: heroContent(autocomplete: "2"))]))

    let plan = palette.tab(shift: false)

    #expect(plan.queryText == "2")
    #expect(plan.queryFieldText == "2")
    #expect(plan.query.mode == .general, "autocomplete must not cycle the tab row")
}

@MainActor
@Test
func shiftTabAlwaysCyclesEvenWithAnAutocompletingHero() {
    let palette = state(orderedModes: [.general, .apps, .fileSearch])
    let query = ParsedQuery(mode: .general, term: "1+1")
    palette.setQueryText("1+1")
    palette.apply(update(query, [row("calc", hero: heroContent(autocomplete: "2"))]))

    #expect(palette.tab(shift: true).query.mode == .fileSearch)
}

// MARK: - Lifecycle

@MainActor
@Test
func resetClearsEverythingIncludingTheRenderKey() {
    let palette = state()
    let query = ParsedQuery(mode: .clipboard, term: "")
    palette.enterMode(.clipboard)
    let results = [row("a")]
    palette.apply(update(query, results))

    let cleared = palette.reset()
    #expect(cleared.queryText.isEmpty)
    #expect(cleared.rows.isEmpty)
    #expect(cleared.focus == .none)
    #expect(cleared.query.mode == .general)

    // The adapter emptied its views on hide, so identical content afterwards
    // still has to be treated as new.
    palette.setQueryText("")
    let redrawn = palette.apply(
        update(ParsedQuery(mode: .general, term: ""), results)
    )
    #expect(redrawn.contentChanged)
}

// MARK: - Repro

@MainActor
@Test
func leavingEmojiModeSearchesTheNewModeNotEmoji() {
    let palette = state()
    palette.enterMode(.emoji)
    palette.apply(
        update(ParsedQuery(mode: .emoji, term: ""), [row("tile0"), row("tile1")])
    )

    let entered = palette.enterMode(.apps)
    #expect(entered.query.mode == .apps)

    let typed = palette.setQueryText("saf")
    #expect(typed.query.mode == .apps, "still querying emoji after leaving the tab")
    #expect(typed.effects == [.runQuery(ParsedQuery(mode: .apps, term: "saf"))])

    let results = palette.apply(
        update(ParsedQuery(mode: .apps, term: "saf"), [row("app:safari")])
    )
    #expect(results.rows.map(\.id) == ["app:safari"])
    #expect(results.presentation == .list)
}
