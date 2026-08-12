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

/// No key window at all reads the same whether the user left or an in-app
/// handover has not settled, so the successor alone cannot decide it.
///
/// Seen live, both as `successor=nil`: Quick Look takes key only after loading
/// its preview and gives it up again on the way out, and one deferred runloop
/// turn lands in between. Hiding on the bare nil tore the palette down mid-open
/// and took Quick Look with it.
@MainActor
@Test
func noSuccessorIsAFocusLossOnlyWhenNoOverlayIsLeft() {
    let own = makePalettePanel()

    #expect(
        FocusLossCheck.isForeign(
            successor: nil,
            ownPanel: own,
            otherOverlayIsVisible: false
        ),
        "nothing of ours on screen — the user really has gone"
    )
    #expect(
        !FocusLossCheck.isForeign(
            successor: nil,
            ownPanel: own,
            otherOverlayIsVisible: true
        ),
        "an overlay of ours is still up, so focus never left the app"
    )
}

/// A window that is not ours still wins, overlay or not: the user clicked into
/// another app while Quick Look happened to be open.
@MainActor
@Test
func aForeignSuccessorWinsEvenWithAnOverlayUp() {
    let foreign = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )

    #expect(
        FocusLossCheck.isForeign(
            successor: foreign,
            ownPanel: makePalettePanel(),
            otherOverlayIsVisible: true
        )
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
