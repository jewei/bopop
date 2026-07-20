import AppKit
import Sparkle

@MainActor
final class AppUpdater {
    private let delegate = UpdaterDelegate()
    private let controller: SPUStandardUpdaterController

    weak var settingsModel: SettingsModel? {
        get { delegate.settingsModel }
        set { delegate.settingsModel = newValue }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: delegate
        )
    }

    func checkForUpdates() {
        // Sparkle's windows need Dock/Cmd-Tab presence while visible;
        // the delegate restores .accessory when the session ends.
        NSApp.setActivationPolicy(.regular)
        controller.updater.checkForUpdates()
    }
}

// Sparkle invokes these on the main thread; @preconcurrency satisfies the
// nonisolated ObjC protocol from this MainActor-isolated class.
private final class UpdaterDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var settingsModel: SettingsModel?

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Handle background scheduled finds ourselves (gentle path);
        // let Sparkle show UI for checks the user explicitly triggered.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            NSApp.setActivationPolicy(.regular)
        } else {
            settingsModel?.updateAvailable = true
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        settingsModel?.updateAvailable = false
    }

    func standardUserDriverWillFinishUpdateSession() {
        settingsModel?.updateAvailable = false
        // Keep the app activatable while our Settings window is open —
        // dropping an LSUIElement app to .accessory with a visible window
        // strands it without Cmd-Tab focus. Sparkle's own windows are
        // closing at this point; match ours by title.
        let settingsOpen = NSApp.windows.contains {
            $0.isVisible && $0.title == "Bopop Settings"
        }
        if !settingsOpen { NSApp.setActivationPolicy(.accessory) }
    }
}
