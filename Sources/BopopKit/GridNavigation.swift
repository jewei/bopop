import Foundation

/// Pure index arithmetic for the emoji tile grid — extracted so
/// `PaletteController` doesn't have to hand-roll row/column math, and so
/// the edge cases (first-row up, last-partial-row down, rightmost →) are
/// covered by fast unit tests instead of manual QA.
public nonisolated enum GridNavigation {
    /// `columns`/`count` describe the grid's row-major shape (the last row
    /// may be partial, e.g. `count: 24, columns: 10` has a 4-tile third
    /// row). `by` is the raw index delta a caller wants to apply — ±1 for
    /// left/right, ±`columns` for up/down.
    ///
    /// Clamped to `0..<count`, never wraps past either edge. The single
    /// clamp also naturally "snaps" an out-of-range vertical move to the
    /// nearest valid tile: moving down from a column that doesn't exist in
    /// a partial last row lands on the last real tile rather than
    /// refusing to move or wrapping around to row 0.
    public static func move(index: Int, by offset: Int, columns: Int, count: Int) -> Int {
        guard count > 0 else {
            return 0
        }
        return min(max(index + offset, 0), count - 1)
    }
}
