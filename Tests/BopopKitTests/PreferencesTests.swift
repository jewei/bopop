import Foundation
import Testing
@testable import BopopKit

@Test
func persistedPreferenceKeysMatchShippedNamesAndAreUnique() {
    let expected = [
        "hotkeyKeyCode",
        "hotkeyModifiers",
        "clipboardLimit",
        "currencyConversionEnabled",
        "chineseVariant",
        "searchEngine",
        "fileSearchFolders",
        "customSearches",
        "suppressSpotlightConflictWarning",
        "palettePositionTopLeftX",
        "palettePositionTopLeftY"
    ]

    #expect(PersistedPreferenceKeys.allRawValues.sorted() == expected.sorted())
    #expect(Set(PersistedPreferenceKeys.allRawValues).count == expected.count)
}

@Test
func typedPreferenceAccessorsPreserveMissingNumericValues() {
    let suite = "PreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.number(for: PersistedPreferenceKeys.hotkeyKeyCode) == nil)
    #expect(defaults.number(for: PersistedPreferenceKeys.palettePositionX) == nil)
}

@Test
func typedPreferenceAccessorsRoundTripSupportedShapes() {
    let suite = "PreferencesTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let data = Data("value".utf8)

    defaults.set(UInt32(12), for: PersistedPreferenceKeys.hotkeyKeyCode)
    defaults.set(UInt(42), for: PersistedPreferenceKeys.hotkeyModifiers)
    defaults.set(250, for: PersistedPreferenceKeys.clipboardLimit)
    defaults.set(true, for: PersistedPreferenceKeys.currencyEnabled)
    defaults.set("traditional", for: PersistedPreferenceKeys.chineseVariant)
    defaults.set(["~/Documents"], for: PersistedPreferenceKeys.fileSearchFolders)
    defaults.set(data, for: PersistedPreferenceKeys.customSearchesData)
    defaults.set(123.5, for: PersistedPreferenceKeys.palettePositionX)

    #expect(defaults.number(for: PersistedPreferenceKeys.hotkeyKeyCode)?.uint32Value == 12)
    #expect(defaults.number(for: PersistedPreferenceKeys.hotkeyModifiers)?.uintValue == 42)
    #expect(defaults.number(for: PersistedPreferenceKeys.clipboardLimit)?.intValue == 250)
    #expect(defaults.bool(for: PersistedPreferenceKeys.currencyEnabled))
    #expect(defaults.string(for: PersistedPreferenceKeys.chineseVariant) == "traditional")
    #expect(defaults.stringArray(for: PersistedPreferenceKeys.fileSearchFolders) == ["~/Documents"])
    #expect(defaults.data(for: PersistedPreferenceKeys.customSearchesData) == data)
    #expect(defaults.number(for: PersistedPreferenceKeys.palettePositionX)?.doubleValue == 123.5)
}
