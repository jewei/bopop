import Testing
@testable import BopopKit

// Resting tab row used throughout, mirroring `PaletteTabsView.orderedTabs`'s
// modes (title/symbol are UI-only and irrelevant to the pure cycling math).
private let orderedModes: [Mode] = [.general, .apps, .fileSearch, .clipboard, .emoji, .translation]

@Test
func tabCyclingForwardAdvancesToNextMode() {
    #expect(TabCycling.next(from: .general, offset: 1, orderedModes: orderedModes) == .apps)
}

@Test
func tabCyclingBackwardRetreatsToPreviousMode() {
    #expect(TabCycling.next(from: .apps, offset: -1, orderedModes: orderedModes) == .general)
}

@Test
func tabCyclingForwardWrapsPastLastMode() {
    #expect(TabCycling.next(from: .translation, offset: 1, orderedModes: orderedModes) == .general)
}

@Test
func tabCyclingBackwardWrapsPastFirstMode() {
    #expect(TabCycling.next(from: .general, offset: -1, orderedModes: orderedModes) == .translation)
}

// The regression this batch fixes: a transient mode (e.g. `.snippets`) has
// no resting slot in `orderedModes`, so naively defaulting its "current
// index" to 0 and then cycling from there overshoots past `.general` in
// either direction. Both keys must land squarely on `.general` instead.
@Test
func tabCyclingForwardFromUnlistedModeLandsOnGeneral() {
    #expect(TabCycling.next(from: .snippets, offset: 1, orderedModes: orderedModes) == .general)
}

@Test
func tabCyclingBackwardFromUnlistedModeLandsOnGeneral() {
    #expect(TabCycling.next(from: .snippets, offset: -1, orderedModes: orderedModes) == .general)
}

@Test
func tabCyclingEmptyOrderedModesReturnsCurrent() {
    #expect(TabCycling.next(from: .snippets, offset: 1, orderedModes: []) == .snippets)
}
