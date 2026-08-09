import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var hasCenteredWindow = false
    private var windowCloseObserver: NotificationToken?

    /// Deliberately not `lazy var`: `isVisible` has to answer "is Settings
    /// open?" without building the window as a side effect of asking.
    private var builtWindow: NSWindow?

    private var window: NSWindow {
        if let builtWindow {
            return builtWindow
        }
        let hostingController = NSHostingController(
            rootView: SettingsView(model: model)
        )
        let window = SettingsWindow(contentViewController: hostingController)
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

        builtWindow = window
        return window
    }

    init(model: SettingsModel) {
        self.model = model
    }

    var isVisible: Bool {
        builtWindow?.isVisible == true
    }

    func show() {
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Bring an already-open Settings window forward without the centering
    /// pass `show()` does — used when reopening the app should reveal the
    /// window the user already has, not move it.
    func focusExisting() {
        guard let builtWindow, builtWindow.isVisible else {
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        builtWindow.makeKeyAndOrderFront(nil)
    }
}

/// There is no menu bar in an accessory app, so the standard Close key
/// equivalent never reaches this window. Route it by hand.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.relevantModifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
