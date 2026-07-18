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
