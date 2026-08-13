import Foundation
import Testing
@testable import BopopKit

@MainActor
private func repository() -> (PreferencesRepository, UserDefaults) {
    let suite = "PreferencesRepositoryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (PreferencesRepository(defaults: defaults), defaults)
}

@MainActor
@Test func preferenceDefaultsAndTypedRoundTrips() throws {
    let (preferences, _) = repository()
    #expect(preferences.clipboardLimit == 100)
    #expect(preferences.chineseVariant == .chineseSimplified)
    #expect(preferences.searchEngine == .google)
    #expect(preferences.palettePosition == nil)

    preferences.setClipboardLimit(900)
    preferences.setCurrencyEnabled(true)
    preferences.setChineseVariant(.chineseTraditional)
    preferences.setSearchEngine(.duckDuckGo)
    preferences.setFileSearchFolders(["/tmp"])
    preferences.setPalettePosition(PalettePosition(x: 12, top: 34))

    #expect(preferences.clipboardLimit == 500)
    #expect(preferences.currencyEnabled)
    #expect(preferences.chineseVariant == .chineseTraditional)
    #expect(preferences.searchEngine == .duckDuckGo)
    #expect(preferences.fileSearchFolders == ["/tmp"])
    #expect(preferences.palettePosition == PalettePosition(x: 12, top: 34))
}

@MainActor
@Test func customSearchEncodingIsOwnedByRepository() throws {
    let (preferences, _) = repository()
    let search = CustomWebSearch(
        id: UUID(), name: "Example", keyword: "ex",
        urlTemplate: "https://example.com/?q={query}"
    )
    try preferences.setCustomSearches([search])
    #expect(preferences.customSearches == [search])
}
