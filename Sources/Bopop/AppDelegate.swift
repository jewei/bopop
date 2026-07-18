import AppKit
import BopopKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.oneone.bopop", category: "app")
    private let storage: Storage
    private let usageStore: UsageStore
    private let clipboardStore: ClipboardStore
    private let pasteboardWatcher: PasteboardWatcher
    private let appCatalog: AppCatalog
    private let paletteController: PaletteController
    private let hotkeyManager = HotkeyManager()
    private var statusItem: NSStatusItem?

    override init() {
        let storage = Storage.production()
        let usageStore = UsageStore(storage: storage)
        let clipboardStore = ClipboardStore(storage: storage)
        let pasteboardWatcher = PasteboardWatcher(store: clipboardStore)
        let appCatalog = AppCatalog()
        let appsProvider = AppsProvider(
            catalog: appCatalog,
            frecencyFor: usageStore.score
        )
        let scriptCatalog = ScriptCatalog(directory: storage.scriptsDirectory)
        let engine = QueryEngine(
            providers: [
                .general: [
                    CommandsProvider(),
                    appsProvider,
                    CalculatorProvider(),
                    ScriptsProvider(catalog: scriptCatalog)
                ],
                .fileSearch: [
                    FileSearchProvider(searcher: FileSearcher())
                ],
                .clipboard: [ClipboardProvider(store: clipboardStore)]
            ],
            frecencyFor: usageStore.score
        )
        let scriptFeedback = ScriptFeedback(storage: storage)
        let actionRunner = ActionRunner(
            storage: storage,
            scriptFeedback: scriptFeedback
        )
        actionRunner.onExecuted = { usageStore.record($0.id) }
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

        let hotkeyConfig = HotkeyConfig.load(from: .standard)
        hotkeyManager.onHotkey = { [weak self] in
            self?.paletteController.toggle()
        }
        hotkeyManager.register(hotkeyConfig)
        DispatchQueue.main.async {
            SpotlightConflict.warnIfConflicting(with: hotkeyConfig)
        }
    }

    @objc private func showBopop() {
        paletteController.toggle()
    }

    @objc private func showSettings() {
        logger.info("Settings selected")
    }

    @objc private func openScriptsFolder() {
        NSWorkspace.shared.open(storage.scriptsDirectory)
    }

    @objc private func quitBopop() {
        NSApp.terminate(nil)
    }
}
