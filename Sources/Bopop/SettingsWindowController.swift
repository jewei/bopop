import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var hasCenteredWindow = false
    private var windowCloseObserver: NotificationToken?

    private lazy var window: NSWindow = {
        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Bopop Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false

        windowCloseObserver = NotificationToken(
            name: NSWindow.willCloseNotification,
            object: window
        ) {
            // Opening Settings promotes the app to .regular, and a Sparkle
            // update session may have too (see AppUpdater) — drop back once
            // nothing else needs Cmd-Tab presence. This window is still in
            // NSApp.windows while it closes, hence `excluding`.
            ActivationPolicy.restoreAccessoryWhenNothingNeedsFocus(excluding: window)
        }

        return window
    }()

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
