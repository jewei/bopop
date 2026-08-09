import Testing
@testable import BopopKit

@Test
func paletteSelectionResolvesUpdateDefaults() {
    #expect(
        PaletteSelection.afterUpdate(
            rowIDs: [],
            hasHero: false,
            restorationID: nil,
            isFinal: true
        ) == .init(index: 0, restorationID: nil)
    )
    #expect(
        PaletteSelection.afterUpdate(
            rowIDs: ["row"],
            hasHero: true,
            restorationID: nil,
            isFinal: false
        ) == .init(index: PaletteSelection.heroIndex, restorationID: nil)
    )
}

@Test
func paletteSelectionRestoresRowsAheadOfHero() {
    #expect(
        PaletteSelection.afterUpdate(
            rowIDs: ["first", "selected"],
            hasHero: true,
            restorationID: "selected",
            isFinal: false
        ) == .init(index: 1, restorationID: "selected")
    )
}

@Test
func paletteSelectionKeepsRestorationThroughIncrementalUpdates() {
    let missing = PaletteSelection.afterUpdate(
        rowIDs: ["other"],
        hasHero: true,
        restorationID: "selected",
        isFinal: false
    )
    #expect(missing == .init(index: PaletteSelection.heroIndex, restorationID: "selected"))

    let found = PaletteSelection.afterUpdate(
        rowIDs: ["other", "selected"],
        hasHero: true,
        restorationID: missing.restorationID,
        isFinal: false
    )
    #expect(found == .init(index: 1, restorationID: "selected"))

    let final = PaletteSelection.afterUpdate(
        rowIDs: ["selected", "other"],
        hasHero: true,
        restorationID: found.restorationID,
        isFinal: true
    )
    #expect(final == .init(index: 0, restorationID: nil))
}

@Test
func paletteSelectionConsumesMissingRestorationOnFinalUpdate() {
    #expect(
        PaletteSelection.afterUpdate(
            rowIDs: ["other"],
            hasHero: false,
            restorationID: "missing",
            isFinal: true
        ) == .init(index: 0, restorationID: nil)
    )
}

@Test
func paletteSelectionMovesTableWithinHeroAwareBounds() {
    #expect(PaletteSelection.moveTable(index: -1, by: -1, rowCount: 2, hasHero: true) == -1)
    #expect(PaletteSelection.moveTable(index: -1, by: 1, rowCount: 2, hasHero: true) == 0)
    #expect(PaletteSelection.moveTable(index: 0, by: -1, rowCount: 2, hasHero: true) == -1)
    #expect(PaletteSelection.moveTable(index: 0, by: -1, rowCount: 2, hasHero: false) == 0)
    #expect(PaletteSelection.moveTable(index: 1, by: 10, rowCount: 2, hasHero: false) == 1)
    #expect(PaletteSelection.moveTable(index: -1, by: 1, rowCount: 0, hasHero: true) == -1)
    #expect(PaletteSelection.moveTable(index: 0, by: 1, rowCount: 0, hasHero: false) == 0)
}

@Test
func paletteSelectionMovesGridThroughExistingPolicy() {
    #expect(PaletteSelection.moveGrid(index: -1, by: 1, columns: 10, rowCount: 24) == 1)
    #expect(PaletteSelection.moveGrid(index: 0, by: -1, columns: 10, rowCount: 24) == 0)
    #expect(PaletteSelection.moveGrid(index: 19, by: 10, columns: 10, rowCount: 24) == 23)
    #expect(PaletteSelection.moveGrid(index: 4, by: 10, columns: 10, rowCount: 0) == 4)
}

@Test
func paletteSelectionMapsSentinelAndRowsToIDs() {
    #expect(
        PaletteSelection.selectedID(
            index: PaletteSelection.heroIndex,
            heroID: "hero",
            rowIDs: ["row"]
        ) == "hero"
    )
    #expect(
        PaletteSelection.selectedID(
            index: PaletteSelection.heroIndex,
            heroID: nil,
            rowIDs: ["row"]
        ) == nil
    )
    #expect(PaletteSelection.selectedID(index: 0, heroID: "hero", rowIDs: ["row"]) == "row")
    #expect(PaletteSelection.selectedID(index: -2, heroID: "hero", rowIDs: ["row"]) == nil)
    #expect(PaletteSelection.selectedID(index: 1, heroID: "hero", rowIDs: ["row"]) == nil)
}
