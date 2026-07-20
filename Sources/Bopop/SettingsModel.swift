import BopopKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class SettingsModel: ObservableObject {
    static let clipboardLimitKey = "clipboardLimit"
    static let chineseVariantKey = "chineseVariant"
    static let searchEngineKey = "searchEngine"

    @Published var hotkey: HotkeyConfig {
        didSet {
            hotkeyManager.register(hotkey)
            hotkey.save(to: defaults)
            spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        }
    }

    @Published var isRecording = false {
        didSet {
            guard isRecording != oldValue else {
                return
            }
            if isRecording {
                hotkeyManager.unregister()
            } else {
                hotkeyManager.register(hotkey)
            }
        }
    }

    @Published var clipboardLimit: Int {
        didSet {
            let clamped = Self.clampClipboardLimit(clipboardLimit)
            guard clipboardLimit == clamped else {
                clipboardLimit = clamped
                return
            }
            defaults.set(clipboardLimit, forKey: Self.clipboardLimitKey)
            clipboardStore.setLimit(clipboardLimit)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            updateLaunchAtLogin(from: oldValue)
        }
    }

    @Published var chineseVariant: TranslationTarget {
        didSet {
            defaults.set(chineseVariant.rawValue, forKey: Self.chineseVariantKey)
        }
    }

    @Published var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Self.searchEngineKey)
        }
    }

    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var spotlightConflict: Bool

    private let hotkeyManager: HotkeyManager
    private let clipboardStore: ClipboardStore
    private let defaults: UserDefaults
    private var isRevertingLaunchAtLogin = false

    init(
        hotkeyManager: HotkeyManager,
        clipboardStore: ClipboardStore,
        defaults: UserDefaults = .standard
    ) {
        let hotkey = HotkeyConfig.load(from: defaults)
        self.hotkeyManager = hotkeyManager
        self.clipboardStore = clipboardStore
        self.defaults = defaults
        self.hotkey = hotkey
        clipboardLimit = Self.storedClipboardLimit(in: defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        chineseVariant = Self.storedChineseVariant(in: defaults)
        searchEngine = Self.storedSearchEngine(in: defaults)
    }

    static func storedClipboardLimit(in defaults: UserDefaults) -> Int {
        guard let stored = defaults.object(forKey: clipboardLimitKey) as? NSNumber else {
            return 100
        }
        return clampClipboardLimit(stored.intValue)
    }

    static func storedChineseVariant(in defaults: UserDefaults) -> TranslationTarget {
        guard let stored = defaults.string(forKey: chineseVariantKey),
              let target = TranslationTarget(rawValue: stored) else {
            return .chineseSimplified
        }
        return target
    }

    static func storedSearchEngine(in defaults: UserDefaults) -> SearchEngine {
        guard let stored = defaults.string(forKey: searchEngineKey),
              let engine = SearchEngine(rawValue: stored) else {
            return .google
        }
        return engine
    }

    func recheckConflict() {
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        hotkeyManager.register(hotkey)
    }

    private static func clampClipboardLimit(_ value: Int) -> Int {
        min(max(value, 10), 500)
    }

    private func updateLaunchAtLogin(from oldValue: Bool) {
        guard launchAtLogin != oldValue, !isRevertingLaunchAtLogin else {
            return
        }

        launchAtLoginError = nil
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginError = error.localizedDescription
            isRevertingLaunchAtLogin = true
            launchAtLogin = oldValue
            isRevertingLaunchAtLogin = false
        }
    }
}
