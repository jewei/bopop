import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

// The shipping design tokens, checked against the rules they feed. The rules
// themselves are tested in BopopKitTests/PaletteGeometryTests; this is the one
// assertion that needs the real numbers, which live in the app target.

/// The shipping tokens, sanity-checked: whatever the design says, the palette
/// must not be taller than a small laptop's usable height at full capacity.
@Test
func theShippingGeometryStaysWithinASmallScreen() {
    let tallest = max(
        PaletteMetrics.geometry.panelHeight(resultCount: 1914, hasHero: true, isGrid: false),
        PaletteMetrics.geometry.panelHeight(resultCount: 1914, hasHero: false, isGrid: true)
    )

    #expect(tallest < 800)
}
