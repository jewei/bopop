import AppKit
import BopopKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.oneone.bopop", category: "app")
    private let storage = Storage.production()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? storage.ensureDirectories()

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
    }

    @objc private func showBopop() {
        logger.info("Show Bopop selected")
    }

    @objc private func showSettings() {
        logger.info("Settings selected")
    }

    @objc private func openScriptsFolder() {
        logger.info("Open Scripts Folder selected")
    }

    @objc private func quitBopop() {
        NSApp.terminate(nil)
    }
}
