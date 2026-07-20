import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var hasCenteredWindow = false

    private lazy var window: NSWindow = {
        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Bopop Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            // A Sparkle update session may have promoted the app to .regular
            // while Settings was open (see AppUpdater); dropping back here
            // keeps the LSUIElement app out of the Dock once no window needs
            // Cmd-Tab presence. Sparkle windows are not titled "Bopop
            // Settings", so check for any other visible regular window.
            Task { @MainActor in
                let otherVisible = NSApp.windows.contains {
                    $0.isVisible && $0 !== window && !($0 is NSPanel)
                }
                if !otherVisible { NSApp.setActivationPolicy(.accessory) }
            }
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
