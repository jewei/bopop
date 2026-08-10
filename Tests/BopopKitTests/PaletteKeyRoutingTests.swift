import Foundation
import Testing
@testable import BopopKit

// The key matrix, asserted in one place.
//
// It used to live in three files: the ⌘-chord table on PalettePanel, a closure
// per chord on PaletteController, and the selector switch in `doCommandBy`.
// Nothing tested which key reached which destination under which overlay
// state, and the rules that mattered most were duplicated — the
// overlay-dismiss-beats-panel-gating precedence twice, once for Quick Look and
// once for Large Type, and the grid/text ←→ asymmetry three times, twice as
// prose comments.

@MainActor
private func palette(
    grid: Bool = false,
    focused: SearchResult? = nil
) -> PaletteState {
    let state = PaletteState(
        configuration: PaletteStateConfiguration(
            orderedModes: [.general, .apps, .emoji],
            gridColumns: 10
        )
    )
    let mode: Mode = grid ? .emoji : .general
    state.enterMode(mode)
    if let focused {
        state.apply(
            QueryEngine.Update(
                query: ParsedQuery(mode: mode, term: ""),
                results: [focused],
                generation: 1,
                isFinal: true
            )
        )
    }
    return state
}

/// Primary action is not itself a copy, so the actions panel offers a
/// separate Copy row and ⌘C has something to run.
private nonisolated func copyableResult() -> SearchResult {
    SearchResult(
        id: "app",
        providerID: .apps,
        title: "Safari",
        action: .openApp("/Applications/Safari.app"),
        secondaryActions: [.copyText("Safari")],
        sortHint: 0
    )
}

/// Primary action IS a copy, so the panel deliberately shows no duplicate
/// Copy row — see `ResultActions.items(for:)`.
private nonisolated func alreadyCopyResult() -> SearchResult {
    SearchResult(
        id: "text",
        providerID: .clipboard,
        title: "Some text",
        action: .copyText("Some text"),
        sortHint: 0
    )
}

private nonisolated func fileResult() -> SearchResult {
    SearchResult(
        id: "file",
        providerID: .files,
        title: "Report.pdf",
        action: .openFile("/tmp/Report.pdf"),
        sortHint: 0
    )
}

// MARK: - Navigation

@MainActor
@Test
func arrowsMoveTheSelectionWithNoOverlayOpen() {
    let state = palette()

    #expect(state.route(.up, overlays: PaletteOverlays()) == .perform(.moveSelection(.up)))
    #expect(state.route(.down, overlays: PaletteOverlays()) == .perform(.moveSelection(.down)))
}

/// The asymmetry, stated once. In the list ←/→ are caret motion and must reach
/// AppKit; reporting them handled would silently swallow the keystroke.
@MainActor
@Test
func horizontalArrowsBelongToTheCaretInTheListAndTheGridSelectionInTheGrid() {
    #expect(palette(grid: false).route(.left, overlays: PaletteOverlays()) == .passThrough)
    #expect(palette(grid: false).route(.right, overlays: PaletteOverlays()) == .passThrough)
    #expect(
        palette(grid: true).route(.left, overlays: PaletteOverlays())
            == .perform(.moveSelection(.left))
    )
    #expect(
        palette(grid: true).route(.right, overlays: PaletteOverlays())
            == .perform(.moveSelection(.right))
    )
}

@MainActor
@Test
func tabCyclesAndEnterRunsAndEscapeEscapes() {
    let state = palette()

    #expect(state.route(.tab, overlays: PaletteOverlays()) == .perform(.cycleTab(shift: false)))
    #expect(state.route(.backTab, overlays: PaletteOverlays()) == .perform(.cycleTab(shift: true)))
    #expect(state.route(.enter, overlays: PaletteOverlays()) == .perform(.runFocused))
    #expect(state.route(.escape, overlays: PaletteOverlays()) == .perform(.escape))
}

// MARK: - While the actions panel is open

@MainActor
@Test
func theOpenActionsPanelClaimsTheNavigationKeys() {
    let state = palette()
    let open = PaletteOverlays(actionsPanelIsVisible: true)

    #expect(state.route(.up, overlays: open) == .perform(.actionsPanelMove(-1)))
    #expect(state.route(.down, overlays: open) == .perform(.actionsPanelMove(1)))
    #expect(state.route(.enter, overlays: open) == .perform(.actionsPanelRunSelected))
    #expect(state.route(.escape, overlays: open) == .perform(.actionsPanelDismiss))
}

/// ⇥ is deliberately not claimed: it still cycles the tab row, and the query
/// change that follows closes the panel on its own.
@MainActor
@Test
func tabStillCyclesWhileTheActionsPanelIsOpen() {
    let state = palette()

    #expect(
        state.route(.tab, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .perform(.cycleTab(shift: false))
    )
}

/// In the grid these are swallowed so the tiles don't move out from under the
/// panel, leaving it showing a stale result's actions. In the list they are
/// still caret motion.
@MainActor
@Test
func horizontalArrowsAreSwallowedInTheGridWhileThePanelIsOpen() {
    let open = PaletteOverlays(actionsPanelIsVisible: true)

    #expect(palette(grid: true).route(.left, overlays: open) == .perform(.swallow))
    #expect(palette(grid: true).route(.right, overlays: open) == .perform(.swallow))
    #expect(palette(grid: false).route(.left, overlays: open) == .passThrough)
    #expect(palette(grid: false).route(.right, overlays: open) == .passThrough)
}

// MARK: - Command chords

/// Panel-only: with the panel closed ⌘C has to reach the field editor so the
/// user can copy selected query text.
@MainActor
@Test
func commandCopyPassesThroughToTheFieldEditorUnlessThePanelOffersIt() {
    let state = palette(focused: copyableResult())

    #expect(state.route(.commandCopy, overlays: PaletteOverlays()) == .passThrough)
    #expect(
        state.route(.commandCopy, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .perform(.actionsPanelRun(.copy))
    )
}

/// A result the panel cannot service passes the key through rather than
/// swallowing it.
@MainActor
@Test
func aChordThePanelCannotServicePassesThrough() {
    let state = palette(focused: alreadyCopyResult())

    #expect(
        state.route(.commandReveal, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .passThrough,
        "a clipboard text row has no file to reveal"
    )
    #expect(
        state.route(.commandQuickLook, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .passThrough,
        "and nothing to Quick Look"
    )
}

/// The chord follows the panel's copy-dedup rule rather than second-guessing
/// it: a row whose primary action is already a copy has no Copy item, so ⌘C
/// keeps its field-editor meaning even with the panel open.
@MainActor
@Test
func commandCopyPassesThroughWhenThePrimaryActionIsItselfACopy() {
    let state = palette(focused: alreadyCopyResult())

    #expect(
        state.route(.commandCopy, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .passThrough
    )
}

@MainActor
@Test
func commandRevealRunsForAResultThatHasAFile() {
    let state = palette(focused: fileResult())

    #expect(
        state.route(.commandReveal, overlays: PaletteOverlays(actionsPanelIsVisible: true))
            == .perform(.actionsPanelRun(.reveal))
    )
}

/// The precedence that was written out twice: an overlay already up is
/// dismissed by its own key, whether or not the actions panel is also open.
@MainActor
@Test
func anOpenOverlayIsDismissedByItsOwnKeyRegardlessOfThePanel() {
    let state = palette(focused: fileResult())

    for panelOpen in [false, true] {
        #expect(
            state.route(
                .commandQuickLook,
                overlays: PaletteOverlays(
                    actionsPanelIsVisible: panelOpen,
                    quickLookIsVisible: true
                )
            ) == .perform(.toggleQuickLook)
        )
        #expect(
            state.route(
                .commandLargeType,
                overlays: PaletteOverlays(
                    actionsPanelIsVisible: panelOpen,
                    largeTypeIsVisible: true
                )
            ) == .perform(.toggleLargeType)
        )
    }
}

@MainActor
@Test
func theAlwaysAvailableChordsDoNotDependOnAnyOverlay() {
    let state = palette()

    for overlays in [
        PaletteOverlays(),
        PaletteOverlays(actionsPanelIsVisible: true),
        PaletteOverlays(quickLookIsVisible: true, largeTypeIsVisible: true)
    ] {
        #expect(state.route(.commandActions, overlays: overlays) == .perform(.toggleActionsPanel))
        #expect(state.route(.commandSettings, overlays: overlays) == .perform(.showSettings))
        #expect(state.route(.commandClose, overlays: overlays) == .perform(.closePalette))
    }
}

/// Nothing may be silently dropped: every key has a decision in every overlay
/// combination, and a `.swallow` is only ever deliberate.
@MainActor
@Test
func everyKeyIsDecidedInEveryOverlayCombination() {
    let state = palette(focused: fileResult())
    var swallowed: [PaletteKey] = []

    for panel in [false, true] {
        for quickLook in [false, true] {
            for largeType in [false, true] {
                let overlays = PaletteOverlays(
                    actionsPanelIsVisible: panel,
                    quickLookIsVisible: quickLook,
                    largeTypeIsVisible: largeType
                )
                for key in PaletteKey.allCases
                where state.route(key, overlays: overlays) == .perform(.swallow) {
                    swallowed.append(key)
                }
            }
        }
    }

    #expect(swallowed.isEmpty, "nothing is swallowed in list mode: \(swallowed)")
}
