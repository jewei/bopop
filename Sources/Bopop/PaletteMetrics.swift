import AppKit

enum PaletteMetrics {
    static let width: CGFloat = 620
    static let fieldHeight: CGFloat = 76
    static let separatorHeight: CGFloat = 1
    static let tabsHeight: CGFloat = 40
    static let tabPillHeight: CGFloat = 26
    static let rowHeight: CGFloat = 52
    static let maxVisibleRows = 9
    static let heroHeight: CGFloat = 96
    static let listTopInset: CGFloat = 8
    static let listSideInset: CGFloat = 10
    static let listBottomInset: CGFloat = 14
    static let interRowGap: CGFloat = 4
    static let footerHeight: CGFloat = 40
    static let cornerRadius: CGFloat = 20
    static let headerInset: CGFloat = 24
    static let footerInset: CGFloat = 22
    static let rowContentPadding: CGFloat = 14
    static let selectionRadius: CGFloat = 10
    static let iconSize: CGFloat = 32
    static let tileRadius: CGFloat = 8
    // Brand keycap (drawn, not the icns — see PaletteBrandView), sized to
    // balance the 34pt query font.
    static let brandSquareSize: CGFloat = 36

    // Emoji tile grid (EmojiGridView) — a view swap on the same
    // scroll-area real estate the table occupies, so it reuses
    // listSideInset/listTopInset/listBottomInset for its contentInsets.
    static let gridColumns = 10
    static let gridVisibleRows = 5
    static let gridTileSize: CGFloat = 52
    static let gridTileRadius: CGFloat = 10
    static let gridGlyphSize: CGFloat = 28
    // Interitem/line spacing computed so exactly `gridColumns` tiles fill
    // the panel's content width edge-to-edge (no leftover partial column,
    // no asymmetric trailing gap) rather than hand-picking a magic number.
    static let gridSpacing: CGFloat = {
        let contentWidth = width - listSideInset * 2
        let columns = CGFloat(gridColumns)
        return (contentWidth - columns * gridTileSize) / (columns - 1)
    }()
}
