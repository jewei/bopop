import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

/// `applicationShouldHandleReopen` asks this before deciding whether to summon
/// the palette. If the check itself built the window, every reopen would create
/// an off-screen Settings window and the palette would never surface again.
@MainActor
@Test
func settingsWindowIsNotConsideredVisibleBeforeItIsEverShown() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-settings-window-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    let suite = "com.oneone.bopop.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let controller = SettingsWindowController(
        model: SettingsModel(
            hotkeyManager: HotkeyManager(),
            clipboardStore: ClipboardStore(storage: storage),
            snippetStore: SnippetStore(storage: storage),
            visibilityStore: VisibilityStore(storage: storage),
            rateStore: RateStore(storage: storage),
            storage: storage,
            defaults: defaults
        )
    )

    #expect(!controller.isVisible)
    // Still false on a second read — a memoizing getter would have built and
    // cached a window on the first one.
    #expect(!controller.isVisible)
}
