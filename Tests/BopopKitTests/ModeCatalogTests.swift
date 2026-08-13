import Testing
@testable import BopopKit

@Test func everyModeHasOneDescriptor() {
    #expect(Mode.descriptors.map(\.mode) == Mode.allCases)
    #expect(Set(Mode.descriptors.map(\.mode)).count == Mode.descriptors.count)
}

@Test func restingModesAndPresentationsComeFromCatalog() {
    #expect(Mode.restingModes == [
        .general, .apps, .fileSearch, .clipboard, .emoji, .translation
    ])
    #expect(Mode.emoji.descriptor.presentation == .grid)
    #expect(Mode.snippets.descriptor.tabPlacement == .transient)
    #expect(Mode.general.descriptor.title == "All")
}
