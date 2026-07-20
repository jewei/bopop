import Foundation

public nonisolated enum TabKeyAction: Equatable, Sendable {
    case autocomplete(String)
    case cycleTab
}

/// ⇥ cycles the tab row — except while a hero that opts in via
/// `HeroContent.autocompleteText` is showing (currently just the
/// calculator's), where it feeds that text back into the query so
/// calculation can continue.
public nonisolated enum TabKeyPolicy {
    public static func action(hero: SearchResult?) -> TabKeyAction {
        guard let answer = hero?.hero?.autocompleteText else {
            return .cycleTab
        }
        return .autocomplete(answer)
    }
}

/// Pure index arithmetic for ⇥/⇧⇥ cycling through the resting tab row —
/// extracted so `PaletteController.cycleTab` doesn't hand-roll the
/// current-index lookup, and so the edge case of an unlisted current mode
/// is covered by fast unit tests instead of manual QA.
public nonisolated enum TabCycling {
    /// `orderedModes` is the resting tab row in display order (e.g.
    /// `PaletteTabsView.orderedTabs`'s modes). `offset` is ±1 for ⇥/⇧⇥.
    ///
    /// When `current` isn't one of `orderedModes` — a transient mode with no
    /// resting slot, like `.snippets` — both directions land on the first
    /// ordered mode rather than defaulting the "current index" to 0 and
    /// cycling off an assumed slot (which would overshoot past it).
    public static func next(from current: Mode, offset: Int, orderedModes: [Mode]) -> Mode {
        guard !orderedModes.isEmpty else {
            return current
        }
        guard let currentIndex = orderedModes.firstIndex(of: current) else {
            return orderedModes[0]
        }
        let count = orderedModes.count
        let nextIndex = ((currentIndex + offset) % count + count) % count
        return orderedModes[nextIndex]
    }
}
