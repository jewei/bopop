import Foundation
import Testing
@testable import BopopKit

// The panel-height rules, which were `private static` on PaletteController and
// unreachable from any test. Every one of them is user-visible: get the cap
// wrong and the panel grows past the screen, get the partial-row ceiling wrong
// and the last row of emoji is clipped.

/// Deliberately round, unlike the shipping design tokens — these tests are
/// about the rules, and real numbers would make every expectation a magic
/// constant nobody can check by eye.
private let geometry = PaletteGeometry(
    chromeHeight: 100,
    heroHeight: 90,
    listTopInset: 5,
    listBottomInset: 5,
    rowHeight: 50,
    interRowGap: 10,
    maxVisibleRows: 9,
    gridColumns: 10,
    gridVisibleRows: 5,
    gridTileSize: 50,
    gridSpacing: 10
)

@Test
func anEmptyListCollapsesToTheChrome() {
    #expect(geometry.listContentHeight(resultCount: 0) == 0)
    #expect(geometry.panelHeight(resultCount: 0, hasHero: false, isGrid: false) == 100)
}

@Test
func listHeightCountsGapsBetweenRowsNotAfterThem() {
    // 3 rows, 2 gaps: 150 + 20 + insets.
    #expect(geometry.listContentHeight(resultCount: 3) == 180)
    // One row has no gap at all.
    #expect(geometry.listContentHeight(resultCount: 1) == 60)
}

/// The cap is what stops a long result set growing the panel off the screen.
@Test
func theListStopsGrowingAtTheVisibleRowCap() {
    let atCap = geometry.listContentHeight(resultCount: 9)
    #expect(geometry.listContentHeight(resultCount: 10) == atCap)
    #expect(geometry.listContentHeight(resultCount: 1914) == atCap)
}

@Test
func aHeroAddsItsOwnBand() {
    let withoutHero = geometry.panelHeight(resultCount: 3, hasHero: false, isGrid: false)
    let withHero = geometry.panelHeight(resultCount: 3, hasHero: true, isGrid: false)

    #expect(withHero - withoutHero == 100, "hero height plus its insets")
}

@Test
func anEmptyGridCollapsesToo() {
    #expect(geometry.gridContentHeight(resultCount: 0) == 0)
    #expect(geometry.panelHeight(resultCount: 0, hasHero: false, isGrid: true) == 100)
}

/// A partial last row still occupies a whole row — 11 tiles at 10 columns is
/// two rows, not 1.1.
@Test
func aPartialLastTileRowStillTakesAWholeRow() {
    let oneRow = geometry.gridContentHeight(resultCount: 10)
    let twoRows = geometry.gridContentHeight(resultCount: 11)

    #expect(oneRow == 60)
    #expect(twoRows == 120, "50 + 50 tiles, one 10pt gap, insets")
    #expect(geometry.gridContentHeight(resultCount: 20) == twoRows)
}

@Test
func theGridStopsGrowingAtItsOwnVisibleRowCap() {
    let atCap = geometry.gridContentHeight(resultCount: 50)
    #expect(geometry.gridContentHeight(resultCount: 51) == atCap)
    // The full emoji catalogue must not produce a panel 192 rows tall.
    #expect(geometry.gridContentHeight(resultCount: 1914) == atCap)
}

/// The two presentations cap independently, so a mode swap changes the height
/// even on the same result count.
@Test
func listAndGridCapAtDifferentHeights() {
    let list = geometry.panelHeight(resultCount: 1914, hasHero: false, isGrid: false)
    let grid = geometry.panelHeight(resultCount: 1914, hasHero: false, isGrid: true)

    #expect(list != grid)
}
