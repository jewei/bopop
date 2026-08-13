import AppKit
import Testing
@testable import Bopop

/// The HUD is the only place an action failure or a script result can appear —
/// the palette is already gone by then. A `show()` that silently does nothing
/// makes both invisible.
@MainActor
@Test func showingTheHUDPutsAVisiblePanelOnScreen() {
    let hud = MessageHUDController()
    defer { hud.hide() }

    hud.show("a message worth reading", isFailure: false)

    let panel = hud.visiblePanelForTesting
    #expect(panel != nil)
    #expect(panel?.isVisible == true)
    #expect((panel?.frame.height ?? 0) > 0)
    #expect((panel?.frame.width ?? 0) > 0)
}

/// The HUD was invisible in the running app while passing the test above: it
/// was built by hand at `.floating` with no collection behaviour, so it lived
/// on one Space and sat below any full-screen app. Every other Bopop overlay
/// goes through `applyBopopOverlayStyle`; this one must too.
@MainActor
@Test func theHUDUsesTheSharedOverlayStyle() {
    let hud = MessageHUDController()
    defer { hud.hide() }

    hud.show("a message", isFailure: false)
    let panel = hud.visiblePanelForTesting
    #expect(panel != nil)

    // Not asserting the level: `applyBopopOverlayStyle` sets `.statusBar` and
    // then `isFloatingPanel = true`, which resets it to `.floating`. Every
    // Bopop overlay has shipped at that level and works; the collection
    // behaviour below is what was actually missing.
    #expect(panel?.collectionBehavior.contains(.canJoinAllSpaces) == true)
    #expect(panel?.collectionBehavior.contains(.fullScreenAuxiliary) == true)
    #expect(panel?.hidesOnDeactivate == false)
}

/// A panel can be on screen at the right size and still show nothing, so check
/// that the content actually paints: sample the middle of the rendered view and
/// require an opaque dark pixel rather than transparency.
@MainActor
@Test func theHUDActuallyPaintsItsBackground() throws {
    let hud = MessageHUDController()
    defer { hud.hide() }
    hud.show("a message worth reading", isFailure: false)

    let content = try #require(hud.visiblePanelForTesting?.contentView)
    content.layoutSubtreeIfNeeded()
    let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
    content.cacheDisplay(in: content.bounds, to: rep)

    // Well left of the centred label, and clear of the 12pt rounded corner.
    let background = try #require(rep.colorAt(x: 24, y: rep.pixelsHigh / 2))
    #expect(background.alphaComponent > 0.9, "background should be opaque, got \(background)")
    #expect(background.brightnessComponent < 0.3, "background should be dark, got \(background)")

    // And the label itself paints: light pixels somewhere along the middle row.
    let hasText = (0..<rep.pixelsWide).contains { x in
        (rep.colorAt(x: x, y: rep.pixelsHigh / 2)?.brightnessComponent ?? 0) > 0.7
    }
    #expect(hasText, "the message text should be painted")
}
