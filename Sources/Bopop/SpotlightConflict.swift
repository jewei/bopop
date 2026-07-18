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

    static func warnIfConflicting(with config: HotkeyConfig) {
        guard isConflicting(with: config) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "⌘Space is taken by Spotlight"
        alert.informativeText = "Bopop's shortcut won't fire until Spotlight's \"Show Spotlight search\" shortcut is disabled in System Settings → Keyboard → Keyboard Shortcuts."
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Later")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        NSWorkspace.shared.open(keyboardSettingsURL)
    }
}
