import AppKit
import BopopKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let storage: Storage
    private let usageStore: UsageStore
    private let clipboardStore: ClipboardStore
    private let pasteboardWatcher: PasteboardWatcher
    private let appCatalog: AppCatalog
    private let paletteController: PaletteController
    private let hotkeyManager: HotkeyManager
    private let settingsModel: SettingsModel
    private let settingsWindowController: SettingsWindowController
    private var statusItem: NSStatusItem?

    override init() {
        let defaults = UserDefaults.standard
        let storage = Storage.production()
        let usageStore = UsageStore(storage: storage)
        let clipboardLimit = SettingsModel.storedClipboardLimit(in: defaults)
        let clipboardStore = ClipboardStore(storage: storage, limit: clipboardLimit)
        let pasteboardWatcher = PasteboardWatcher(store: clipboardStore)
        let appCatalog = AppCatalog()
        let hotkeyManager = HotkeyManager()
        let appsProvider = AppsProvider(
            catalog: appCatalog,
            frecencyFor: usageStore.score
        )
        let scriptCatalog = ScriptCatalog(directory: storage.scriptsDirectory)
        // EmojiProvider's frecency hook must be a plain @Sendable closure
        // (it's invoked off the main actor during concurrent provider
        // ranking); UsageStore itself is main-actor isolated, so bridge
        // through assumeIsolated rather than relaxing UsageStore's isolation.
        let emojiFrecencyFor: @Sendable (String) -> Double = { id in
            MainActor.assumeIsolated { usageStore.score(id) }
        }
        // settingsModel is constructed AFTER this engine (it needs
        // hotkeyManager/clipboardStore which are wired up below), so this
        // closure must not capture settingsModel — it reads defaults
        // directly via the same static-read pattern as
        // storedClipboardLimit, avoiding the ordering trap. It's invoked
        // off the main actor during concurrent provider ranking (same
        // reasoning as emojiFrecencyFor above), so bridge through
        // assumeIsolated rather than relaxing SettingsModel's isolation.
        let chineseVariantFor: @Sendable () -> TranslationTarget = {
            MainActor.assumeIsolated { SettingsModel.storedChineseVariant(in: .standard) }
        }
        let appleTranslator = AppleTranslator(defaults: defaults)
        let engine = QueryEngine(
            providers: [
                .general: [
                    CommandsProvider(),
                    appsProvider,
                    CalculatorProvider(),
                    ScriptsProvider(catalog: scriptCatalog),
                    CurrencyProvider(store: RateStore(storage: storage), fetcher: LiveRateFetcher()),
                    TimeProvider(),
                    URLCleanProvider()
                ],
                .fileSearch: [
                    FileSearchProvider(searcher: FileSearcher())
                ],
                .clipboard: [ClipboardProvider(store: clipboardStore)],
                .emoji: [
                    EmojiProvider(catalog: EmojiCatalog(), frecencyFor: emojiFrecencyFor)
                ],
                .translation: [
                    TranslationProvider(
                        translator: appleTranslator,
                        chineseVariant: chineseVariantFor
                    )
                ]
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
        self.storage = storage
        self.usageStore = usageStore
        self.clipboardStore = clipboardStore
        self.pasteboardWatcher = pasteboardWatcher
        self.appCatalog = appCatalog
        paletteController = PaletteController(
            engine: engine,
            actionRunner: actionRunner,
            onWillShow: appCatalog.refreshIfStale
        )
        self.hotkeyManager = hotkeyManager
        let settingsModel = SettingsModel(
            hotkeyManager: hotkeyManager,
            clipboardStore: clipboardStore,
            defaults: defaults
        )
        self.settingsModel = settingsModel
        settingsWindowController = SettingsWindowController(model: settingsModel)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? storage.ensureDirectories()
        pasteboardWatcher.start()
        appCatalog.refreshIfStale()

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let image = NSImage(
                systemSymbolName: "command.square.fill",
                accessibilityDescription: "Bopop"
            ) {
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "B"
            }
        }

        let menu = NSMenu()
        let showItem = NSMenuItem(
            title: "Show Bopop",
            action: #selector(showBopop),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let scriptsItem = NSMenuItem(
            title: "Open Scripts Folder",
            action: #selector(openScriptsFolder),
            keyEquivalent: ""
        )
        scriptsItem.target = self
        menu.addItem(scriptsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Bopop",
            action: #selector(quitBopop),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem

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

    @objc private func showBopop() {
        paletteController.toggle()
    }

    @objc private func showSettings() {
        settingsWindowController.show()
    }

    @objc private func openScriptsFolder() {
        NSWorkspace.shared.open(storage.scriptsDirectory)
    }

    @objc private func quitBopop() {
        NSApp.terminate(nil)
    }
}
