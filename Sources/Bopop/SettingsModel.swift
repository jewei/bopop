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
            hotkey.save(to: defaults)
            spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
            // Recording writes the new binding before it flips `isRecording`
            // back to false. Register only on that final transition so one
            // recording produces one Carbon registration, not two.
            if !isRecording {
                registerCurrentHotkey()
            }
        }
    }

    @Published var isRecording = false {
        didSet {
            guard isRecording != oldValue else {
                return
            }
            if isRecording {
                hotkeyManager.unregister()
                hotkeyRegistrationOutcome = nil
            } else {
                registerCurrentHotkey()
            }
        }
    }

    @Published var clipboardLimit: Int {
        didSet {
            let clamped = PreferencesRepository.clampClipboardLimit(clipboardLimit)
            guard clipboardLimit == clamped else {
                clipboardLimit = clamped
                return
            }
            preferences.setClipboardLimit(clipboardLimit)
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
            preferences.setChineseVariant(chineseVariant)
        }
    }

    @Published var searchEngine: SearchEngine {
        didSet {
            preferences.setSearchEngine(searchEngine)
        }
    }

    @Published private(set) var fileSearchFolders: [String] {
        didSet {
            preferences.setFileSearchFolders(fileSearchFolders)
        }
    }

    @Published private(set) var customSearches: [CustomWebSearch] {
        didSet {
            try? preferences.setCustomSearches(customSearches)
        }
    }

    @Published private(set) var snippets: [Snippet]
    /// Results hidden via the ⌘K panel. Settings is the only way back.
    @Published private(set) var hiddenResultIDs: [String]

    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var currencyCacheError: String?
    @Published private(set) var spotlightConflict: Bool
    /// Carbon's local registration result. It can diagnose Bopop's own handler
    /// or registration failure, but it cannot establish that another process
    /// owns the same combination. Spotlight remains a separate explicit check.
    @Published private(set) var hotkeyRegistrationOutcome: HotkeyRegistrationOutcome?
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

    private let hotkeyManager: any HotkeyRegistering
    private let clipboardStore: ClipboardStore
    private let snippetStore: SnippetStore
    private let visibilityStore: VisibilityStore
    private let rateStore: RateStore
    private let storage: Storage
    private let defaults: UserDefaults
    private let preferences: PreferencesRepository
    private var isRevertingLaunchAtLogin = false

    init(
        hotkeyManager: any HotkeyRegistering,
        clipboardStore: ClipboardStore,
        snippetStore: SnippetStore,
        visibilityStore: VisibilityStore,
        rateStore: RateStore,
        storage: Storage,
        defaults: UserDefaults = .standard,
        preferences: PreferencesRepository? = nil
    ) {
        let hotkey = HotkeyConfig.load(from: defaults)
        let preferences = preferences ?? PreferencesRepository(defaults: defaults)
        self.hotkeyManager = hotkeyManager
        self.clipboardStore = clipboardStore
        self.snippetStore = snippetStore
        self.visibilityStore = visibilityStore
        self.rateStore = rateStore
        self.storage = storage
        self.defaults = defaults
        self.preferences = preferences
        self.hotkey = hotkey
        clipboardLimit = preferences.clipboardLimit
        currencyEnabled = preferences.currencyEnabled
        launchAtLogin = SMAppService.mainApp.status == .enabled
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        chineseVariant = preferences.chineseVariant
        searchEngine = preferences.searchEngine
        fileSearchFolders = preferences.fileSearchFolders
        customSearches = preferences.customSearches
        snippets = snippetStore.snippets
        snippetsAvailable = snippetStore.isAvailable
        hiddenResultIDs = visibilityStore.hiddenIDs.sorted()
        hasCustomBrandImage = FileManager.default.fileExists(atPath: storage.brandImageURL.path)
    }

    static func storedClipboardLimit(in defaults: UserDefaults) -> Int {
        PreferencesRepository(defaults: defaults).clipboardLimit
    }

    /// Absent means off. Currency is the only query feature that makes a
    /// network request, so it ships disabled until the user consents. Sparkle
    /// update checks are disclosed separately.
    static func storedCurrencyEnabled(in defaults: UserDefaults) -> Bool {
        PreferencesRepository(defaults: defaults).currencyEnabled
    }

    /// `enabled == true` is only ever reached from the consent dialog in
    /// `SettingsView`. Turning it off deletes the cached rate table.
    func setCurrencyEnabled(_ enabled: Bool) {
        guard enabled != currencyEnabled else {
            return
        }
        currencyEnabled = enabled
        preferences.setCurrencyEnabled(enabled)
        if !enabled {
            if case let .failure(error) = rateStore.clearCache() {
                currencyCacheError = "Currency is off, but the cached rates could not be deleted: \(error.reason)"
            } else {
                currencyCacheError = nil
            }
        }
    }

    static func storedChineseVariant(in defaults: UserDefaults) -> TranslationTarget {
        PreferencesRepository(defaults: defaults).chineseVariant
    }

    static func storedSearchEngine(in defaults: UserDefaults) -> SearchEngine {
        PreferencesRepository(defaults: defaults).searchEngine
    }

    static func storedFileSearchFolders(in defaults: UserDefaults) -> [String] {
        PreferencesRepository(defaults: defaults).fileSearchFolders
    }

    static func storedCustomSearches(in defaults: UserDefaults) -> [CustomWebSearch] {
        PreferencesRepository(defaults: defaults).customSearches
    }

    /// Re-runs both checks and retries the registration, so freeing the
    /// shortcut in the other app and pressing Re-check is enough — no relaunch.
    func recheckConflict() {
        spotlightConflict = SpotlightConflict.isConflicting(with: hotkey)
        registerCurrentHotkey()
    }

    /// Records the result of AppDelegate's launch-time registration without
    /// asking Carbon twice.
    func setHotkeyRegistrationOutcome(_ outcome: HotkeyRegistrationOutcome) {
        hotkeyRegistrationOutcome = outcome
    }

    private func registerCurrentHotkey() {
        hotkeyRegistrationOutcome = hotkeyManager.register(hotkey)
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

    /// Maps the domain validation result to presentation copy. The rules
    /// themselves live on `CustomWebSearch`, so Settings cannot drift from the
    /// provider's definition of a usable search.
    private static func validate(
        _ search: CustomWebSearch,
        against existing: [CustomWebSearch]
    ) -> CustomSearchError? {
        switch search.validationError(existing: existing) {
        case .none: nil
        case .nameMissing: .nameMissing
        case .keywordMissing: .keywordMissing
        case .keywordHasWhitespace: .keywordHasWhitespace
        case .keywordReserved: .keywordReserved
        case .keywordTaken: .keywordTaken
        case .templateMissingQueryToken: .templateMissingQueryToken
        }
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
        do {
            if FileManager.default.fileExists(atPath: storage.brandImageURL.path) {
                try FileManager.default.removeItem(at: storage.brandImageURL)
            }
            hasCustomBrandImage = false
        } catch {
            brandImageImportError = "Couldn't reset the palette icon: \(error.localizedDescription)"
        }
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
