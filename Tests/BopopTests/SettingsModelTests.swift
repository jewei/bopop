import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

private func makeDefaults() -> UserDefaults {
    let suite = "com.oneone.bopop.tests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

/// AppDelegate reads the limit through this static before any SettingsModel
/// exists, so an out-of-range stored value has to be clamped here rather than
/// only in the `@Published` didSet.
@Test func storedClipboardLimitClampsOutOfRangeValues() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 100)

    defaults.set(9_999, forKey: SettingsModel.clipboardLimitKey)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 500)

    defaults.set(1, forKey: SettingsModel.clipboardLimitKey)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(-40, forKey: SettingsModel.clipboardLimitKey)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(250, forKey: SettingsModel.clipboardLimitKey)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 250)
}

@Test func storedEnumsFallBackWhenMissingOrUnrecognized() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set("not-a-variant", forKey: SettingsModel.chineseVariantKey)
    defaults.set("not-an-engine", forKey: SettingsModel.searchEngineKey)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set(TranslationTarget.chineseTraditional.rawValue, forKey: SettingsModel.chineseVariantKey)
    defaults.set(SearchEngine.duckDuckGo.rawValue, forKey: SettingsModel.searchEngineKey)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseTraditional)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .duckDuckGo)
}

@Test func storedCustomSearchesSurvivesGarbageWithoutThrowing() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    defaults.set(Data("not json".utf8), forKey: SettingsModel.customSearchesKey)
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    let search = CustomWebSearch(
        id: UUID(), name: "Docs", keyword: "d", urlTemplate: "https://example.com/?q={query}"
    )
    defaults.set(try? JSONEncoder().encode([search]), forKey: SettingsModel.customSearchesKey)
    #expect(SettingsModel.storedCustomSearches(in: defaults) == [search])
}
