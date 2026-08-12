import AppKit
import BopopKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class SettingsModel: ObservableObject {
    /// Why an add was refused. The form used to just return `false` and clear
    /// nothing, so a rejected entry looked identical to a slow one.
    enum CustomSearchError: Equatable {
        case nameMissing
        case keywordMissing
        case keywordHasWhitespace
        case keywordReserved
        case keywordTaken
        case templateMissingQueryToken

        var message: String {
            switch self {
            case .nameMissing:
                "Give the search a name."
            case .keywordMissing:
                "Give the search a keyword."
            case .keywordHasWhitespace:
                "Keywords can't contain spaces."
            case .keywordReserved:
                "\"f\", \"t\", and keywords starting with \":\" are reserved."
            case .keywordTaken:
                "That keyword is already used by another search."
            case .templateMissingQueryToken:
                "The URL needs a {query} placeholder."
            }
        }
    }

    enum SnippetError: Equatable {
        case nameMissing
        case contentMissing
        case storageUnavailable
        case saveFailed(String)

        var message: String {
            switch self {
            case .nameMissing:
                "Give the snippet a name."
            case .contentMissing:
                "Give the snippet some content."
            case .storageUnavailable:
                """
                Your snippets file couldn't be read and was renamed to \
                snippets.json.corrupt in Bopop's Application Support folder. \
                Snippets stay read-only until you move or delete it.
                """
            case .saveFailed(let reason):
                "Couldn't save snippets: \(reason)"
            }
        }
    }

    @Published var hotkey: HotkeyConfig {
        didSet {
            hotkeyUnavailable = !hotkeyManager.register(hotkey)
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
            defaults.set(clipboardLimit, for: PersistedPreferenceKeys.clipboardLimit)
            clipboardStore.setLimit(clipboardLimit)
        }
    }

    /// Read-only from the view's perspective: turning it ON goes through
    /// `confirmCurrencyConsent()` so the disclosure can't be bypassed by
    /// binding a toggle straight to it.
    @Published private(set) var currencyEnabled: Bool

    @Published var launchAtLogin: Bool {
        didSet {
            updateLaunchAtLogin(from: oldValue)
        }
    }

    @Published var chineseVariant: TranslationTarget {
        didSet {
            defaults.set(chineseVariant.rawValue, for: PersistedPreferenceKeys.chineseVariant)
        }
    }

    @Published var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, for: PersistedPreferenceKeys.searchEngine)
        }
    }

    @Published private(set) var fileSearchFolders: [String] {
        didSet {
            defaults.set(fileSearchFolders, for: PersistedPreferenceKeys.fileSearchFolders)
        }
    }

    @Published private(set) var customSearches: [CustomWebSearch] {
        didSet {
            guard let data = try? JSONEncoder().encode(customSearches) else {
                return
            }
            defaults.set(data, for: PersistedPreferenceKeys.customSearchesData)
        }
    }

    @Published private(set) var snippets: [Snippet]
    /// Results hidden via the ⌘K panel. Settings is the only way back.
    @Published private(set) var hiddenResultIDs: [String]

    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var spotlightConflict: Bool
    /// The shortcut could not be registered, so it will not fire. Reported by
    /// Carbon at registration time, which catches any app holding the
    /// combination — unlike `spotlightConflict`, which predicts one specific
    /// clash by reading Spotlight's own preferences and only for the default
    /// shortcut.
    @Published private(set) var hotkeyUnavailable = false
    @Published private(set) var customSearchError: CustomSearchError?
    @Published private(set) var snippetError: SnippetError?
    /// False when the snippets file was quarantined at load. Published so the
    /// form can say so up front instead of letting the user compose a snippet
    /// and only then discover it cannot be saved.
    @Published private(set) var snippetsAvailable: Bool

    /// The presence of `storage.brandImageURL` IS the flag — no separate
    /// defaults key, one source of truth (see design doc).
    @Published private(set) var hasCustomBrandImage: Bool
    @Published private(set) var brandImageImportError: String?

    @Published var updateAvailable = false
    /// Wired by AppDelegate to AppUpdater.checkForUpdates(); optional so
    /// SettingsModel stays constructible without Sparkle in previews/tests.
    var checkForUpdates: (() -> Void)?

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private let hotkeyManager: HotkeyManager
    private let clipboardStore: ClipboardStore
    private let snippetStore: SnippetStore
    private let visibilityStore: VisibilityStore
    private let rateStore: RateStore
    private let storage: Storage
    private let defaults: UserDefaults
    private var isRevertingLaunchAtLogin = false

    init(
        hotkeyManager: HotkeyManager,
        clipboardStore: ClipboardStore,
        snippetStore: SnippetStore,
        visibilityStore: VisibilityStore,
        rateStore: RateStore,
        storage: Storage,
        defaults: UserDefaults = .standard
    ) {
        let hotkey = HotkeyConfig.load(from: defaults)
        self.hotkeyManager = hotkeyManager
        self.clipboardStore = clipboardStore
        self.snippetStore = snippetStore
        self.visibilityStore = visibilityStore
        self.rateStore = rateStore
        self.storage = storage
        self.defaults = defaults
        self.hotkey = hotkey
        clipboardLimit = Self.storedClipboardLimit(in: defaults)
        currencyEnabled = Self.storedCurrencyEnabled(in: defaults)
        launchAtLogin = SMAppService.mainApp.status == .enabled
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        chineseVariant = Self.storedChineseVariant(in: defaults)
        searchEngine = Self.storedSearchEngine(in: defaults)
        fileSearchFolders = Self.storedFileSearchFolders(in: defaults)
        customSearches = Self.storedCustomSearches(in: defaults)
        snippets = snippetStore.snippets
        snippetsAvailable = snippetStore.isAvailable
        hiddenResultIDs = visibilityStore.hiddenIDs.sorted()
        hasCustomBrandImage = FileManager.default.fileExists(atPath: storage.brandImageURL.path)
    }

    static func storedClipboardLimit(in defaults: UserDefaults) -> Int {
        guard let stored = defaults.number(for: PersistedPreferenceKeys.clipboardLimit) else {
            return 100
        }
        return clampClipboardLimit(stored.intValue)
    }

    /// Absent means off. Currency conversion is the one feature that leaves
    /// the machine, so it ships disabled and stays disabled until asked for.
    static func storedCurrencyEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(for: PersistedPreferenceKeys.currencyEnabled)
    }

    /// `enabled == true` is only ever reached from the consent dialog in
    /// `SettingsView`. Turning it off deletes the cached rate table.
    func setCurrencyEnabled(_ enabled: Bool) {
        guard enabled != currencyEnabled else {
            return
        }
        currencyEnabled = enabled
        defaults.set(enabled, for: PersistedPreferenceKeys.currencyEnabled)
        if !enabled {
            rateStore.clearCache()
        }
    }

    static func storedChineseVariant(in defaults: UserDefaults) -> TranslationTarget {
        guard let stored = defaults.string(for: PersistedPreferenceKeys.chineseVariant),
              let target = TranslationTarget(rawValue: stored) else {
            return .chineseSimplified
        }
        return target
    }

    static func storedSearchEngine(in defaults: UserDefaults) -> SearchEngine {
        guard let stored = defaults.string(for: PersistedPreferenceKeys.searchEngine),
              let engine = SearchEngine(rawValue: stored) else {
            return .google
        }
        return engine
    }

    static func storedFileSearchFolders(in defaults: UserDefaults) -> [String] {
        defaults.stringArray(for: PersistedPreferenceKeys.fileSearchFolders) ?? []
    }

    static func storedCustomSearches(in defaults: UserDefaults) -> [CustomWebSearch] {
        guard let data = defaults.data(for: PersistedPreferenceKeys.customSearchesData),
              let searches = try? JSONDecoder().decode([CustomWebSearch].self, from: data) else {
            return []
        }
        return searches
    }

    /// Re-runs both checks and retries the registration, so freeing the
    /// shortcut in the other app and pressing Re-check is enough — no relaunch.
    func recheckConflict() {
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        hotkeyUnavailable = !hotkeyManager.register(hotkey)
    }

    /// Seeds the flag from the registration `AppDelegate` performs at launch,
    /// which happens before this model exists.
    func setHotkeyUnavailable(_ unavailable: Bool) {
        hotkeyUnavailable = unavailable
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

    /// A renamed folder or an unmounted drive is skipped silently at query
    /// time (deliberately — see the design doc), which leaves Settings as the
    /// only place that can tell the user a scope has gone dead.
    func isFileSearchFolderMissing(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return !(exists && isDirectory.boolValue)
    }

    /// Appends a new custom search if it's valid and its keyword isn't
    /// already taken by an existing one (case-insensitive, matching
    /// `CustomWebSearch.match`'s lookup). Returns whether it was added, and
    /// publishes `customSearchError` describing any refusal.
    @discardableResult
    func addCustomSearch(name: String, keyword: String, urlTemplate: String) -> Bool {
        let search = CustomWebSearch(id: UUID(), name: name, keyword: keyword, urlTemplate: urlTemplate)
        if let error = Self.validate(search, against: customSearches) {
            customSearchError = error
            return false
        }
        customSearchError = nil
        customSearches.append(search)
        return true
    }

    func clearCustomSearchError() {
        customSearchError = nil
    }

    /// Mirrors `CustomWebSearch.isValid`'s conditions one at a time so the
    /// form can say which one failed. Keep the two in step.
    private static func validate(
        _ search: CustomWebSearch,
        against existing: [CustomWebSearch]
    ) -> CustomSearchError? {
        if search.name.trimmingCharacters(in: .whitespaces).isEmpty {
            return .nameMissing
        }
        if search.keyword.isEmpty {
            return .keywordMissing
        }
        if search.keyword.contains(where: \.isWhitespace) {
            return .keywordHasWhitespace
        }
        if CustomWebSearch.isReservedKeyword(search.keyword) {
            return .keywordReserved
        }
        if !search.urlTemplate.contains("{query}") {
            return .templateMissingQueryToken
        }
        let isTaken = existing.contains {
            $0.keyword.caseInsensitiveCompare(search.keyword) == .orderedSame
        }
        return isTaken ? .keywordTaken : nil
    }

    func removeCustomSearch(id: UUID) {
        customSearches.removeAll { $0.id == id }
    }

    /// Adds a new snippet if name and content are both non-empty once
    /// trimmed. Keyword is optional and stored trimmed; an empty keyword is
    /// stored as `nil`. Returns whether it was added, and publishes
    /// `snippetError` describing any refusal.
    @discardableResult
    func addSnippet(name: String, keyword: String, content: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            snippetError = .nameMissing
            return false
        }
        guard !trimmedContent.isEmpty else {
            snippetError = .contentMissing
            return false
        }
        snippetError = nil
        let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return commitSnippetChange {
            try snippetStore.add(Snippet(
                id: UUID(),
                name: trimmedName,
                keyword: trimmedKeyword.isEmpty ? nil : trimmedKeyword,
                content: trimmedContent
            ))
        }
    }

    func clearSnippetError() {
        snippetError = nil
    }

    @discardableResult
    func updateSnippet(_ snippet: Snippet) -> Bool {
        commitSnippetChange { try snippetStore.update(snippet) }
    }

    /// The store writes to disk before it publishes, so a thrown error means
    /// nothing changed — republish its unchanged list and show why.
    @discardableResult
    private func commitSnippetChange(_ change: () throws -> Void) -> Bool {
        do {
            try change()
            snippetError = nil
        } catch SnippetStore.StoreError.storageUnavailable {
            snippetError = .storageUnavailable
            return false
        } catch let SnippetStore.StoreError.writeFailed(reason) {
            snippetError = .saveFailed(reason)
            return false
        } catch {
            snippetError = .saveFailed(error.localizedDescription)
            return false
        }
        snippets = snippetStore.snippets
        hiddenResultIDs = visibilityStore.hiddenIDs.sorted()
        return true
    }

    func unhideResult(_ id: String) {
        visibilityStore.show(id)
        hiddenResultIDs = visibilityStore.hiddenIDs.sorted()
    }

    @discardableResult
    func removeSnippet(id: UUID) -> Bool {
        commitSnippetChange { try snippetStore.remove(id: id) }
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

    func addFileSearchFolders(_ paths: [String]) {
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
