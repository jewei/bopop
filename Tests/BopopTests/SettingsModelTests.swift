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

    defaults.set(9_999, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 500)

    defaults.set(1, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(-40, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 10)

    defaults.set(250, for: PersistedPreferenceKeys.clipboardLimit)
    #expect(SettingsModel.storedClipboardLimit(in: defaults) == 250)
}

@Test func storedEnumsFallBackWhenMissingOrUnrecognized() {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set("not-a-variant", for: PersistedPreferenceKeys.chineseVariant)
    defaults.set("not-an-engine", for: PersistedPreferenceKeys.searchEngine)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseSimplified)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .google)

    defaults.set(TranslationTarget.chineseTraditional.rawValue, for: PersistedPreferenceKeys.chineseVariant)
    defaults.set(SearchEngine.duckDuckGo.rawValue, for: PersistedPreferenceKeys.searchEngine)
    #expect(SettingsModel.storedChineseVariant(in: defaults) == .chineseTraditional)
    #expect(SettingsModel.storedSearchEngine(in: defaults) == .duckDuckGo)
}

@Test func storedCustomSearchesSurvivesGarbageWithoutThrowing() throws {
    let defaults = makeDefaults()
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    defaults.set(Data("not json".utf8), for: PersistedPreferenceKeys.customSearchesData)
    #expect(SettingsModel.storedCustomSearches(in: defaults).isEmpty)

    let search = CustomWebSearch(
        id: UUID(), name: "Docs", keyword: "d", urlTemplate: "https://example.com/?q={query}"
    )
    defaults.set(
        try JSONEncoder().encode([search]),
        for: PersistedPreferenceKeys.customSearchesData
    )
    #expect(SettingsModel.storedCustomSearches(in: defaults) == [search])
}

@MainActor
@Test func disablingCurrencyClearsTheProvidersLiveRateStore() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-settings-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    let rateStore = RateStore(storage: storage)
    rateStore.save(
        rates: ["EUR": 1, "USD": 1.08],
        fetchedAt: Date(timeIntervalSince1970: 1_000)
    )
    _ = rateStore.cached()

    let defaults = makeDefaults()
    defaults.set(true, for: PersistedPreferenceKeys.currencyEnabled)
    let model = SettingsModel(
        hotkeyManager: HotkeyManager(),
        clipboardStore: ClipboardStore(storage: storage),
        snippetStore: SnippetStore(storage: storage),
        visibilityStore: VisibilityStore(storage: storage),
        rateStore: rateStore,
        storage: storage,
        defaults: defaults
    )

    model.setCurrencyEnabled(false)

    #expect(rateStore.cached() == nil)
    #expect(!FileManager.default.fileExists(atPath: storage.ratesFileURL.path))
}
