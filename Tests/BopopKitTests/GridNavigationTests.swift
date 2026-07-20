import Testing
@testable import BopopKit

// Shape used throughout: 10 columns, 24 items → two full rows (0–9, 10–19)
// plus a partial third row (20–23).

@Test
func gridNavigationMovesRightWithinRow() {
    #expect(GridNavigation.move(index: 5, by: 1, columns: 10, count: 24) == 6)
}

@Test
func gridNavigationMovesLeftWithinRow() {
    #expect(GridNavigation.move(index: 5, by: -1, columns: 10, count: 24) == 4)
}

@Test
func gridNavigationLeftAtStartClampsInPlace() {
    #expect(GridNavigation.move(index: 0, by: -1, columns: 10, count: 24) == 0)
}

@Test
func gridNavigationRightmostAtLastItemClampsInPlace() {
    // Last tile overall (end of the partial third row) — → must not wrap
    // back to index 0.
    #expect(GridNavigation.move(index: 23, by: 1, columns: 10, count: 24) == 23)
}

@Test
func gridNavigationMovesDownAcrossFullRow() {
    #expect(GridNavigation.move(index: 3, by: 10, columns: 10, count: 24) == 13)
}

@Test
func gridNavigationFirstRowUpClampsToZero() {
    // Already in row 0 — ↑ must not wrap to the bottom row.
    #expect(GridNavigation.move(index: 3, by: -10, columns: 10, count: 24) == 0)
}

@Test
func gridNavigationLastPartialRowDownClampsToLastItem() {
    // index 15 is row 1, column 5; row 2 only has columns 0–3, so ↓ snaps
    // to the last real tile (23) instead of overshooting or refusing to move.
    #expect(GridNavigation.move(index: 15, by: 10, columns: 10, count: 24) == 23)
}

@Test
func gridNavigationEmptyGridStaysAtZero() {
    #expect(GridNavigation.move(index: 0, by: 1, columns: 10, count: 0) == 0)
}

@Test
func gridNavigationSingleItemGridStaysAtZero() {
    #expect(GridNavigation.move(index: 0, by: 10, columns: 10, count: 1) == 0)
}
