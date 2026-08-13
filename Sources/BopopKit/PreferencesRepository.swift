import Foundation

public struct PalettePosition: Equatable, Sendable {
    public let x: Double
    public let top: Double

    public init(x: Double, top: Double) {
        self.x = x
        self.top = top
    }
}

/// The typed persistence boundary for user preferences. Features depend on
/// domain values instead of knowing UserDefaults keys, encoding formats and
/// fallback policy independently.
@MainActor
public final class PreferencesRepository {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var clipboardLimit: Int {
        guard let stored = defaults.number(for: PersistedPreferenceKeys.clipboardLimit) else {
            return 100
        }
        return Self.clampClipboardLimit(stored.intValue)
    }

    public func setClipboardLimit(_ limit: Int) {
        defaults.set(Self.clampClipboardLimit(limit), for: PersistedPreferenceKeys.clipboardLimit)
    }

    public var currencyEnabled: Bool {
        defaults.bool(for: PersistedPreferenceKeys.currencyEnabled)
    }

    public func setCurrencyEnabled(_ enabled: Bool) {
        defaults.set(enabled, for: PersistedPreferenceKeys.currencyEnabled)
    }

    public var chineseVariant: TranslationTarget {
        guard let raw = defaults.string(for: PersistedPreferenceKeys.chineseVariant),
              let value = TranslationTarget(rawValue: raw) else {
            return .chineseSimplified
        }
        return value
    }

    public func setChineseVariant(_ variant: TranslationTarget) {
        defaults.set(variant.rawValue, for: PersistedPreferenceKeys.chineseVariant)
    }

    public var searchEngine: SearchEngine {
        guard let raw = defaults.string(for: PersistedPreferenceKeys.searchEngine),
              let value = SearchEngine(rawValue: raw) else {
            return .google
        }
        return value
    }

    public func setSearchEngine(_ engine: SearchEngine) {
        defaults.set(engine.rawValue, for: PersistedPreferenceKeys.searchEngine)
    }

    public var fileSearchFolders: [String] {
        defaults.stringArray(for: PersistedPreferenceKeys.fileSearchFolders) ?? []
    }

    public func setFileSearchFolders(_ folders: [String]) {
        defaults.set(folders, for: PersistedPreferenceKeys.fileSearchFolders)
    }

    public var customSearches: [CustomWebSearch] {
        guard let data = defaults.data(for: PersistedPreferenceKeys.customSearchesData),
              let searches = try? JSONDecoder().decode([CustomWebSearch].self, from: data) else {
            return []
        }
        return searches
    }

    public func setCustomSearches(_ searches: [CustomWebSearch]) throws {
        let data = try JSONEncoder().encode(searches)
        defaults.set(data, for: PersistedPreferenceKeys.customSearchesData)
    }

    public var palettePosition: PalettePosition? {
        guard let x = defaults.number(for: PersistedPreferenceKeys.palettePositionX),
              let top = defaults.number(for: PersistedPreferenceKeys.palettePositionY) else {
            return nil
        }
        return PalettePosition(x: x.doubleValue, top: top.doubleValue)
    }

    public func setPalettePosition(_ position: PalettePosition) {
        defaults.set(position.x, for: PersistedPreferenceKeys.palettePositionX)
        defaults.set(position.top, for: PersistedPreferenceKeys.palettePositionY)
    }

    public var suppressesSpotlightConflictWarning: Bool {
        defaults.bool(for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)
    }

    public func setSuppressesSpotlightConflictWarning(_ suppressed: Bool) {
        defaults.set(suppressed, for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)
    }

    public static func clampClipboardLimit(_ value: Int) -> Int {
        min(max(value, 10), 500)
    }
}
