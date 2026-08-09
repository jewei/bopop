import AppKit
import BopopKit

enum SpotlightConflict {
    static let keyboardSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
    )!

    static func isConflicting(with config: HotkeyConfig) -> Bool {
        guard config == .default else {
            return false
        }

        let symbolicHotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any]
        return SpotlightShortcut.isEnabled(inSymbolicHotkeys: symbolicHotkeys)
    }

    /// Bopop launches at login, so an unsuppressable modal here meant a
    /// dialog on every boot for anyone who keeps ⌘Space on both — "Later"
    /// dismissed it for exactly one launch. Suppressing only silences this
    /// alert: Settings still shows the conflict banner and its "Re-check"
    /// button, so the information stays reachable.
    static func isSuppressed(in defaults: UserDefaults) -> Bool {
        defaults.bool(for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)
    }

    static func warnIfConflicting(
        with config: HotkeyConfig,
        defaults: UserDefaults = .standard
    ) {
        guard isConflicting(with: config), !isSuppressed(in: defaults) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "⌘Space is taken by Spotlight"
        alert.informativeText = "Bopop's shortcut won't fire until Spotlight's \"Show Spotlight search\" shortcut is disabled in System Settings → Keyboard → Keyboard Shortcuts."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't warn me again"

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(true, for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)
        }
        guard response == .alertFirstButtonReturn else {
            return
        }

        NSWorkspace.shared.open(keyboardSettingsURL)
    }
}
