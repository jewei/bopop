import AppKit
import BopopKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class SettingsModel: ObservableObject {
    static let clipboardLimitKey = "clipboardLimit"
    static let chineseVariantKey = "chineseVariant"
    static let searchEngineKey = "searchEngine"
    static let fileSearchFoldersKey = "fileSearchFolders"
    static let customSearchesKey = "customSearches"

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

    @Published private(set) var fileSearchFolders: [String] {
        didSet {
            defaults.set(fileSearchFolders, forKey: Self.fileSearchFoldersKey)
        }
    }

    @Published private(set) var customSearches: [CustomWebSearch] {
        didSet {
            guard let data = try? JSONEncoder().encode(customSearches) else {
                return
            }
            defaults.set(data, forKey: Self.customSearchesKey)
        }
    }

    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var spotlightConflict: Bool

    /// The presence of `storage.brandImageURL` IS the flag — no separate
    /// defaults key, one source of truth (see design doc).
    @Published private(set) var hasCustomBrandImage: Bool
    @Published private(set) var brandImageImportError: String?

    private let hotkeyManager: HotkeyManager
    private let clipboardStore: ClipboardStore
    private let storage: Storage
    private let defaults: UserDefaults
    private var isRevertingLaunchAtLogin = false

    init(
        hotkeyManager: HotkeyManager,
        clipboardStore: ClipboardStore,
        storage: Storage,
        defaults: UserDefaults = .standard
    ) {
        let hotkey = HotkeyConfig.load(from: defaults)
        self.hotkeyManager = hotkeyManager
        self.clipboardStore = clipboardStore
        self.storage = storage
        self.defaults = defaults
        self.hotkey = hotkey
        clipboardLimit = Self.storedClipboardLimit(in: defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        chineseVariant = Self.storedChineseVariant(in: defaults)
        searchEngine = Self.storedSearchEngine(in: defaults)
        fileSearchFolders = Self.storedFileSearchFolders(in: defaults)
        customSearches = Self.storedCustomSearches(in: defaults)
        hasCustomBrandImage = FileManager.default.fileExists(atPath: storage.brandImageURL.path)
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

    static func storedFileSearchFolders(in defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: fileSearchFoldersKey) ?? []
    }

    static func storedCustomSearches(in defaults: UserDefaults) -> [CustomWebSearch] {
        guard let data = defaults.data(forKey: customSearchesKey),
              let searches = try? JSONDecoder().decode([CustomWebSearch].self, from: data) else {
            return []
        }
        return searches
    }

    func recheckConflict() {
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        hotkeyManager.register(hotkey)
    }

    /// Opens an NSOpenPanel (folders only, multi-select) and appends any
    /// newly chosen folders. Duplicates are ignored; a subfolder of an
    /// already-chosen folder is allowed (harmless overlap — see design
    /// doc). Runs modally on the main actor, matching AppKit convention.
    func presentFileSearchFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to search"
        guard panel.runModal() == .OK else {
            return
        }
        addFileSearchFolders(panel.urls.map(\.path))
    }

    func removeFileSearchFolder(_ path: String) {
        fileSearchFolders.removeAll { $0 == path }
    }

    /// Appends a new custom search if it's valid and its keyword isn't
    /// already taken by an existing one (case-insensitive, matching
    /// `CustomWebSearch.match`'s lookup). Returns whether it was added.
    @discardableResult
    func addCustomSearch(name: String, keyword: String, urlTemplate: String) -> Bool {
        let search = CustomWebSearch(id: UUID(), name: name, keyword: keyword, urlTemplate: urlTemplate)
        guard search.isValid,
              !customSearches.contains(where: { $0.keyword.caseInsensitiveCompare(search.keyword) == .orderedSame }) else {
            return false
        }
        customSearches.append(search)
        return true
    }

    func removeCustomSearch(id: UUID) {
        customSearches.removeAll { $0.id == id }
    }

    /// Opens an NSOpenPanel (single image file) and imports the chosen
    /// image as the palette's custom icon. Runs modally on the main actor,
    /// matching `presentFileSearchFolderPicker`'s convention.
    func presentBrandImagePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.prompt = "Choose"
        panel.message = "Choose a palette icon image"
        guard panel.runModal() == .OK, let url = panel.urls.first else {
            return
        }
        importBrandImage(from: url)
    }

    func resetBrandImageToDefault() {
        brandImageImportError = nil
        try? FileManager.default.removeItem(at: storage.brandImageURL)
        hasCustomBrandImage = false
    }

    /// Decode → aspect-fill square-crop → downscale (via
    /// `BrandImageImporter`, a pure function) → write PNG at 0600, mirroring
    /// `Storage.save`'s permission conventions. Import = copy: the original
    /// file at `url` is never referenced again.
    private func importBrandImage(from url: URL) {
        brandImageImportError = nil
        guard let image = NSImage(contentsOf: url),
              let data = BrandImageImporter.importedPNGData(from: image) else {
            brandImageImportError = "Couldn't read that image."
            return
        }
        do {
            try data.write(to: storage.brandImageURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: storage.brandImageURL.path
            )
            hasCustomBrandImage = true
        } catch {
            brandImageImportError = error.localizedDescription
        }
    }

    private func addFileSearchFolders(_ paths: [String]) {
        var updated = fileSearchFolders
        for path in paths where !updated.contains(path) {
            updated.append(path)
        }
        fileSearchFolders = updated
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
