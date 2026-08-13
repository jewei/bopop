import Foundation

public struct PersistedPreferenceKey<Value: Sendable>: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum PersistedPreferenceKeys {
    public static let hotkeyKeyCode = PersistedPreferenceKey<UInt32>("hotkeyKeyCode")
    public static let hotkeyModifiers = PersistedPreferenceKey<UInt>("hotkeyModifiers")
    public static let clipboardLimit = PersistedPreferenceKey<Int>("clipboardLimit")
    public static let currencyEnabled = PersistedPreferenceKey<Bool>("currencyConversionEnabled")
    public static let chineseVariant = PersistedPreferenceKey<String>("chineseVariant")
    public static let searchEngine = PersistedPreferenceKey<String>("searchEngine")
    public static let fileSearchFolders = PersistedPreferenceKey<[String]>("fileSearchFolders")
    public static let customSearchesData = PersistedPreferenceKey<Data>("customSearches")
    public static let suppressSpotlightConflictWarning = PersistedPreferenceKey<Bool>(
        "suppressSpotlightConflictWarning"
    )
    public static let palettePositionX = PersistedPreferenceKey<Double>("palettePositionTopLeftX")
    public static let palettePositionY = PersistedPreferenceKey<Double>("palettePositionTopLeftY")

    public static let allRawValues = [
        hotkeyKeyCode.rawValue,
        hotkeyModifiers.rawValue,
        clipboardLimit.rawValue,
        currencyEnabled.rawValue,
        chineseVariant.rawValue,
        searchEngine.rawValue,
        fileSearchFolders.rawValue,
        customSearchesData.rawValue,
        suppressSpotlightConflictWarning.rawValue,
        palettePositionX.rawValue,
        palettePositionY.rawValue
    ]
}

public extension UserDefaults {
    func number<Value>(
        for key: PersistedPreferenceKey<Value>
    ) -> NSNumber? {
        object(forKey: key.rawValue) as? NSNumber
    }

    func bool(for key: PersistedPreferenceKey<Bool>) -> Bool {
        bool(forKey: key.rawValue)
    }

    func string(for key: PersistedPreferenceKey<String>) -> String? {
        string(forKey: key.rawValue)
    }

    func stringArray(for key: PersistedPreferenceKey<[String]>) -> [String]? {
        stringArray(forKey: key.rawValue)
    }

    func data(for key: PersistedPreferenceKey<Data>) -> Data? {
        data(forKey: key.rawValue)
    }

    func set(_ value: UInt32, for key: PersistedPreferenceKey<UInt32>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: UInt, for key: PersistedPreferenceKey<UInt>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: Int, for key: PersistedPreferenceKey<Int>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: Bool, for key: PersistedPreferenceKey<Bool>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: String, for key: PersistedPreferenceKey<String>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: [String], for key: PersistedPreferenceKey<[String]>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: Data, for key: PersistedPreferenceKey<Data>) {
        set(value, forKey: key.rawValue)
    }

    func set(_ value: Double, for key: PersistedPreferenceKey<Double>) {
        set(value, forKey: key.rawValue)
    }
}
