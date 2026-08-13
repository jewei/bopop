import AppKit
import Quartz
import Testing
@testable import Bopop

// The successor-window allowlist, asserted directly.
//
// This is the hardest behaviour in the app to exercise by hand — it needs a
// real key-window handover between two of Bopop's own overlays — and until the
// decision was split out of the runloop deferral there was nothing to assert
// against. Two commits exist because it was wrong: `cfcbaf5` (hide on focus
// loss while an overlay is key) and `11fb653` (dedupe the checks).

@MainActor
private func makePalettePanel() -> PalettePanel {
    PalettePanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
}

@MainActor
@Test
func ownPanelRegainingKeyIsNotAFocusLoss() {
    let own = makePalettePanel()

    #expect(!FocusLossCheck.isForeign(successor: own, ownPanel: own))
}

@MainActor
@Test
func anotherBopopOverlayTakingKeyIsNotAFocusLoss() {
    let own = makePalettePanel()
    let otherPalette = makePalettePanel()
    let largeType = LargeTypePanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(!FocusLossCheck.isForeign(successor: otherPalette, ownPanel: own))
    #expect(!FocusLossCheck.isForeign(successor: largeType, ownPanel: own))
}

@MainActor
@Test
func anUnrelatedWindowTakingKeyIsAFocusLoss() {
    let own = makePalettePanel()
    let foreign = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )

    #expect(FocusLossCheck.isForeign(successor: foreign, ownPanel: own))
}

@MainActor
@Test
func quickLookOpeningIsAnExplicitInternalHandoff() {
    #expect(
        FocusLossCheck.decision(
            successor: .none,
            handoff: .openingQuickLook,
            retriesRemaining: 0
        ) == .keepFocus
    )
}

@MainActor
@Test
func quickLookResignWaitsForAKeySuccessorThenKeepsOrLosesFocus() {
    #expect(
        FocusLossCheck.decision(
            successor: .none,
            handoff: .resolvingQuickLookResign,
            retriesRemaining: 1
        ) == .retry
    )
    #expect(
        FocusLossCheck.decision(
            successor: .bopopOverlay,
            handoff: .resolvingQuickLookResign,
            retriesRemaining: 0
        ) == .keepFocus,
        "Quick Look's own close handed key back to the palette"
    )
    #expect(
        FocusLossCheck.decision(
            successor: .none,
            handoff: .resolvingQuickLookResign,
            retriesRemaining: 0
        ) == .loseFocus,
        "no successor after the handoff window means the user left the app"
    )
}

@MainActor
@Test
func anotherApplicationsFocusLossIsNilNotItsWindow() {
    #expect(
        FocusLossCheck.decision(
            successor: .none,
            handoff: .stable,
            retriesRemaining: 12
        ) == .loseFocus,
        "NSApp.keyWindow cannot expose another process's key window"
    )
}

/// The coupling CLAUDE.md states in prose, now stated in code.
///
/// `ActionsPanelController` builds a plain `NSPanel`, which is not on the
/// allowlist — so if it ever became key it would read as a genuine focus loss
/// and tear the palette down. It is saved only by borderless panels refusing
/// key by default. This test exists so that "the actions panel never becomes
/// key" stops being a fact you have to already know, and so any future overlay
/// built the same way trips something.
@MainActor
@Test
func aPlainPanelIsForeignWhichIsWhyTheActionsPanelMustNeverBecomeKey() {
    let plain = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    #expect(FocusLossCheck.isForeign(successor: plain, ownPanel: makePalettePanel()))
    #expect(!plain.canBecomeKey, "the only thing keeping the palette alive")
}

/// The regression that shipped when this rule was "any overlay of ours is
/// visible". The palette sits visible behind every overlay, so Large Type
/// resigning while the palette was up read as an in-app handover and Large
/// Type stopped dismissing when the user switched away.
///
/// Caught by QA, not by this file — there was no test for an overlay other
/// than the palette resigning, which is exactly the case the broad rule broke.
@MainActor
@Test
func anOverlayOtherThanTheOwnerStillDismissesOnAGenuineLoss() {
    let largeType = LargeTypePanel(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    // The palette is visible behind it, as it always is. Quick Look is not up,
    // so nothing is mid-handover: this is the user leaving.
    #expect(
        FocusLossCheck.isForeign(
            successor: nil,
            ownPanel: largeType
        ),
        "Large Type must still dismiss with the palette sitting behind it"
    )
}
