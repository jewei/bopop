import Foundation

/// How tall the palette should be for a given result set.
///
/// The rules live here; the numbers do not. Row heights and insets are design
/// tokens that belong with the rest of the design system in the app target —
/// what belongs in the UI-framework-independent module is the arithmetic those tokens
/// feed: cap the list at `maxVisibleRows` then scroll, cap the grid at
/// `gridVisibleRows`, round a partial last tile-row up, and add the hero's
/// band only when there is a hero.
///
/// Those rules were `private static` methods on `PaletteController`, so no test
/// could reach them, and every one of them is user-visible: get the cap wrong
/// and the panel grows past the screen, get the ceiling wrong and the last row
/// of emoji is clipped.
///
/// Dimensions are `Double` rather than `CGFloat` to keep CoreGraphics out of
/// the module. The adapter converts at the call site, where it already deals
/// in `NSRect`.
public struct PaletteGeometry: Equatable, Sendable {
    /// Everything that is on screen regardless of the results: query field,
    /// its separator, the tab row, the footer.
    public let chromeHeight: Double
    public let heroHeight: Double
    public let listTopInset: Double
    public let listBottomInset: Double
    public let rowHeight: Double
    public let interRowGap: Double
    /// List rows shown before the table starts scrolling.
    public let maxVisibleRows: Int
    public let gridColumns: Int
    /// Tile rows shown before the grid starts scrolling.
    public let gridVisibleRows: Int
    public let gridTileSize: Double
    public let gridSpacing: Double

    public init(
        chromeHeight: Double,
        heroHeight: Double,
        listTopInset: Double,
        listBottomInset: Double,
        rowHeight: Double,
        interRowGap: Double,
        maxVisibleRows: Int,
        gridColumns: Int,
        gridVisibleRows: Int,
        gridTileSize: Double,
        gridSpacing: Double
    ) {
        self.chromeHeight = chromeHeight
        self.heroHeight = heroHeight
        self.listTopInset = listTopInset
        self.listBottomInset = listBottomInset
        self.rowHeight = rowHeight
        self.interRowGap = interRowGap
        self.maxVisibleRows = maxVisibleRows
        self.gridColumns = gridColumns
        self.gridVisibleRows = gridVisibleRows
        self.gridTileSize = gridTileSize
        self.gridSpacing = gridSpacing
    }

    /// Total panel height. `isGrid` and `hasHero` never both hold — emoji mode
    /// produces no hero — but the arithmetic does not depend on that.
    public func panelHeight(
        resultCount: Int,
        hasHero: Bool,
        isGrid: Bool
    ) -> Double {
        let content = isGrid
            ? gridContentHeight(resultCount: resultCount)
            : listContentHeight(resultCount: resultCount)
        let hero = hasHero ? heroHeight + listTopInset + listBottomInset : 0
        return chromeHeight + hero + content
    }

    /// Zero for an empty list, so the panel collapses to its chrome rather
    /// than reserving an empty band.
    public func listContentHeight(resultCount: Int) -> Double {
        let visibleRows = min(resultCount, maxVisibleRows)
        guard visibleRows > 0 else {
            return 0
        }
        return Double(visibleRows) * rowHeight
            + Double(visibleRows - 1) * interRowGap
            + listTopInset
            + listBottomInset
    }

    /// Same cap-then-scroll shape as the list, over tile rows. A partial last
    /// row still occupies a whole row.
    public func gridContentHeight(resultCount: Int) -> Double {
        guard resultCount > 0, gridColumns > 0 else {
            return 0
        }
        let totalRows = (resultCount + gridColumns - 1) / gridColumns
        let visibleRows = min(totalRows, gridVisibleRows)
        return Double(visibleRows) * gridTileSize
            + Double(visibleRows - 1) * gridSpacing
            + listTopInset
            + listBottomInset
    }
}
