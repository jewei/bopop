import Foundation

public nonisolated enum SpotlightShortcut {
    /// Returns whether the Spotlight search symbolic hotkey is enabled.
    /// Missing or malformed values use the macOS default of enabled.
    public static func isEnabled(inSymbolicHotkeys dict: [String: Any]?) -> Bool {
        guard
            let spotlight = dict?["64"] as? [String: Any],
            let enabled = spotlight["enabled"] as? NSNumber
        else {
            return true
        }

        return enabled != 0
    }
}
