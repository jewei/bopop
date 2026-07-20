import AppKit
import BopopKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let storage: Storage
    private let usageStore: UsageStore
    private let clipboardStore: ClipboardStore
    private let snippetStore: SnippetStore
    private let pasteboardWatcher: PasteboardWatcher
    private let appCatalog: AppCatalog
    private let paletteController: PaletteController
    private let hotkeyManager: HotkeyManager
    private let settingsModel: SettingsModel
    private let settingsWindowController: SettingsWindowController
    private let appUpdater: AppUpdater

    override init() {
        let defaults = UserDefaults.standard
        let storage = Storage.production()
        let usageStore = UsageStore(storage: storage)
        let clipboardLimit = SettingsModel.storedClipboardLimit(in: defaults)
        let clipboardStore = ClipboardStore(storage: storage, limit: clipboardLimit)
        let snippetStore = SnippetStore(storage: storage)
        let pasteboardWatcher = PasteboardWatcher(store: clipboardStore)
        let appCatalog = AppCatalog()
        let hotkeyManager = HotkeyManager()
        // AppsProvider/EmojiProvider's frecency hook is invoked off the main
        // actor during concurrent provider ranking; UsageStore itself is
        // main-actor isolated, so hop explicitly via MainActor.run rather
        // than the banned assumeIsolated shortcut. Both providers batch
        // their whole id list through this single hop per results() call
        // (UsageStore.scores(for:)) instead of one hop per id.
        let batchFrecencyFor: BatchFrecencyLookup = { ids in
            await MainActor.run { usageStore.scores(for: ids) }
        }
        let appsProvider = AppsProvider(
            catalog: appCatalog,
            frecencyFor: batchFrecencyFor
        )
        let scriptCatalog = ScriptCatalog(directory: storage.scriptsDirectory)
        // settingsModel is constructed AFTER this engine (it needs
        // hotkeyManager/clipboardStore which are wired up below), so these
        // closures must not capture settingsModel — they read defaults
        // directly via the same static-read pattern as
        // storedClipboardLimit, avoiding the ordering trap. They're invoked
        // off the main actor during concurrent provider ranking (same
        // reasoning as batchFrecencyFor above), so hop via MainActor.run
        // rather than the banned assumeIsolated shortcut.
        let chineseVariantFor: @Sendable () async -> TranslationTarget = {
            await MainActor.run { SettingsModel.storedChineseVariant(in: .standard) }
        }
        let searchEngineFor: @Sendable () async -> SearchEngine = {
            await MainActor.run { SettingsModel.storedSearchEngine(in: .standard) }
        }
        let fileSearchFoldersFor: @Sendable () async -> [String] = {
            await MainActor.run { SettingsModel.storedFileSearchFolders(in: .standard) }
        }
        let customSearchesFor: @Sendable () async -> [CustomWebSearch] = {
            await MainActor.run { SettingsModel.storedCustomSearches(in: .standard) }
        }
        let appleTranslator = AppleTranslator(defaults: defaults)
        let engine = QueryEngine(
            providers: [
                .general: [
                    appsProvider,
                    CalculatorProvider(),
                    ScriptsProvider(catalog: scriptCatalog),
                    CurrencyProvider(store: RateStore(storage: storage), fetcher: LiveRateFetcher()),
                    TimeProvider(),
                    URLCleanProvider(),
                    WebSearchProvider(engine: searchEngineFor),
                    SystemCommandsProvider(),
                    CustomSearchProvider(searches: customSearchesFor),
                    SnippetsProvider(store: snippetStore),
                    CommandsProvider(),
                    DictionaryProvider(lookup: { DictionaryLookup.definition(for: $0) })
                ],
                .apps: [appsProvider],
                .fileSearch: [
                    FileSearchProvider(
                        searcher: FileSearcher(scopeProvider: fileSearchFoldersFor)
                    )
                ],
                .clipboard: [ClipboardProvider(store: clipboardStore)],
                .emoji: [
                    EmojiProvider(catalog: EmojiCatalog(), frecencyFor: batchFrecencyFor)
                ],
                .translation: [
                    TranslationProvider(
                        translator: appleTranslator,
                        chineseVariant: chineseVariantFor
                    )
                ],
                .snippets: [SnippetsProvider(store: snippetStore)]
            ],
            frecencyFor: usageStore.score
        )
        let scriptFeedback = ScriptFeedback(storage: storage)
        let actionRunner = ActionRunner(
            storage: storage,
            clipboardStore: clipboardStore,
            scriptFeedback: scriptFeedback
        )
        actionRunner.onExecuted = { result in
            guard result.action != .clearClipboardHistory else {
                return
            }
            usageStore.record(result.id)
        }
        actionRunner.onDownloadTranslation = { appleTranslator.presentDownloadFlow() }
        self.storage = storage
        self.usageStore = usageStore
        self.clipboardStore = clipboardStore
        self.snippetStore = snippetStore
        self.pasteboardWatcher = pasteboardWatcher
        self.appCatalog = appCatalog
        self.hotkeyManager = hotkeyManager
        let settingsModel = SettingsModel(
            hotkeyManager: hotkeyManager,
            clipboardStore: clipboardStore,
            snippetStore: snippetStore,
            storage: storage,
            defaults: defaults
        )
        self.settingsModel = settingsModel
        // settingsWindowController is built here, ahead of paletteController,
        // so its `show()` can be captured by the closures below — self isn't
        // usable yet (we're still before super.init()), so PaletteController
        // must close over these locals directly rather than over self,
        // mirroring appCatalog.refreshIfStale/emojiFrecencyFor above.
        let settingsWindowController = SettingsWindowController(model: settingsModel)
        self.settingsWindowController = settingsWindowController
        let appUpdater = AppUpdater()
        appUpdater.settingsModel = settingsModel
        settingsModel.checkForUpdates = { appUpdater.checkForUpdates() }
        self.appUpdater = appUpdater
        paletteController = PaletteController(
            engine: engine,
            actionRunner: actionRunner,
            brandImageURL: storage.brandImageURL,
            onWillShow: appCatalog.refreshIfStale,
            onShowSettings: { settingsWindowController.show() },
            onOpenScriptsFolder: { NSWorkspace.shared.open(storage.scriptsDirectory) },
            onQuit: { NSApp.terminate(nil) }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? storage.ensureDirectories()
        pasteboardWatcher.start()
        appCatalog.refreshIfStale()

        let hotkeyConfig = settingsModel.hotkey
        hotkeyManager.onHotkey = { [weak self] in
            self?.paletteController.toggle()
        }
        hotkeyManager.register(hotkeyConfig)
        DispatchQueue.main.async {
            SpotlightConflict.warnIfConflicting(with: hotkeyConfig)
        }
        // Headless smoke hook: BOPOP_DEBUG_AUTOSHOW=1 opens the palette
        // shortly after launch so UI regressions are reproducible without
        // a keyboard (used to catch the row-init exception in 2720f0c-era).
        if ProcessInfo.processInfo.environment["BOPOP_DEBUG_AUTOSHOW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.paletteController.toggle()
            }
        }
    }

    /// Failsafe for a broken/unregistered hotkey: relaunching Bopop while
    /// it's already running (`open dist/Bopop.app`, Spotlight, Dock) fires
    /// this instead of opening a window (the app has none) — surface the
    /// palette directly. `show()` is idempotent, so this is safe even if
    /// the palette is already visible. Returning false tells AppKit there
    /// is no standard window to reveal, since this is an accessory app.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        paletteController.show()
        return false
    }

}
