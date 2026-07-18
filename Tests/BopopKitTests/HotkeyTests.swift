import Foundation
import Testing
@testable import BopopKit

@Test
func carbonModifierMapping() {
    #expect(HotkeyConfig(keyCode: 49, modifiers: [.command]).carbonModifiers == 0x100)
    #expect(
        HotkeyConfig(keyCode: 49, modifiers: [.command, .shift]).carbonModifiers == 0x300
    )
    #expect(HotkeyConfig(keyCode: 49, modifiers: [.option]).carbonModifiers == 0x800)
    #expect(HotkeyConfig(keyCode: 49, modifiers: [.control]).carbonModifiers == 0x1000)
    #expect(
        HotkeyConfig(
            keyCode: 49,
            modifiers: [.command, .shift, .option, .control]
        ).carbonModifiers == 0x1B00
    )
}

@Test
func hotkeyConfigSaveAndLoadRoundTrip() {
    let suiteName = "HotkeyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let expected = HotkeyConfig(keyCode: 12, modifiers: [.command, .option])
    expected.save(to: defaults)

    #expect(HotkeyConfig.load(from: defaults) == expected)
}

@Test
func hotkeyConfigLoadsDefaultFromEmptyDefaults() {
    let suiteName = "HotkeyTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(HotkeyConfig.load(from: defaults) == .default)
}

@Test
func spotlightShortcutDetection() {
    #expect(SpotlightShortcut.isEnabled(inSymbolicHotkeys: nil))
    #expect(SpotlightShortcut.isEnabled(inSymbolicHotkeys: [:]))
    #expect(SpotlightShortcut.isEnabled(inSymbolicHotkeys: ["64": ["enabled": 1]]))
    #expect(!SpotlightShortcut.isEnabled(inSymbolicHotkeys: ["64": ["enabled": 0]]))
    #expect(!SpotlightShortcut.isEnabled(inSymbolicHotkeys: ["64": ["enabled": false]]))
    #expect(SpotlightShortcut.isEnabled(inSymbolicHotkeys: ["64": [:]]))
    #expect(SpotlightShortcut.isEnabled(inSymbolicHotkeys: ["64": "garbage"]))
}
