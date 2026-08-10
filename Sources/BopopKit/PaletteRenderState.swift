import Foundation

/// The content `PaletteController` draws from a `QueryEngine.Update`, in one
/// comparable value.
///
/// The engine publishes at settle boundaries and again when the last provider
/// lands, and those two are frequently identical — the last provider matched
/// nothing. Rebuilding every row view and resizing the panel for that is
/// wasted work the user sees as a twitch, so the controller keeps the last
/// state and skips the reload when the new one compares equal.
///
/// Compares whole `SearchResult`s rather than ids: a row can keep its id while
/// its title, badge or subtitle changes, and skipping the reload on an id match
/// alone would leave the stale text on screen.
///
/// Selection is deliberately absent. It moves under arrow keys without an
/// engine update, so caching it here would go stale; the controller re-applies
/// selection unconditionally instead.
public nonisolated struct PaletteRenderState: Equatable, Sendable {
    public let hero: SearchResult?
    public let rows: [SearchResult]
    /// Which view is on screen. The grid and table never show together, so a
    /// mode swap has to reload even when the rows are unchanged.
    public let isGrid: Bool

    public init(hero: SearchResult?, rows: [SearchResult], isGrid: Bool) {
        self.hero = hero
        self.rows = rows
        self.isGrid = isGrid
    }
}
