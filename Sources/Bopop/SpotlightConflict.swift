import AppKit
import BopopKit

enum SpotlightConflict {
    static func warnIfConflicting(with config: HotkeyConfig) {
        guard config == .default else {
            return
        }

        let symbolicHotkeys = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any]
        guard SpotlightShortcut.isEnabled(inSymbolicHotkeys: symbolicHotkeys) else {
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

        NSWorkspace.shared.open(
            URL(
                string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts"
            )!
        )
    }
}
