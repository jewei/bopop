import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

private func makeSuiteName() -> String {
    "com.oneone.bopop.tests.\(UUID().uuidString)"
}

private func makeDefaults() -> UserDefaults {
    UserDefaults(suiteName: makeSuiteName())!
}

/// Bopop launches at login, so an unsuppressable modal meant a dialog on
/// every boot for anyone keeping ⌘Space on both; "Later" cleared it for
/// exactly one launch. Suppression is only worth anything if it survives
/// relaunch, so re-open the same suite to prove it does.
@Test func spotlightWarningSuppressionSurvivesRelaunch() throws {
    let suiteName = makeSuiteName()
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(!SpotlightConflict.isSuppressed(in: defaults))

    defaults.set(true, for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)
    #expect(SpotlightConflict.isSuppressed(in: defaults))

    // A separate reader of the same suite — what the next launch does.
    let nextLaunch = try #require(UserDefaults(suiteName: suiteName))
    #expect(SpotlightConflict.isSuppressed(in: nextLaunch))
}

/// Suppression silences only the launch alert. `isConflicting` is what the
/// Settings banner reads, and it must stay truthful regardless.
@Test func suppressionDoesNotChangeConflictDetection() {
    let defaults = makeDefaults()
    defaults.set(true, for: PersistedPreferenceKeys.suppressSpotlightConflictWarning)

    // A non-default hotkey never conflicts, suppressed or not.
    let custom = HotkeyConfig(keyCode: 49, modifiers: [.control, .option])
    #expect(!SpotlightConflict.isConflicting(with: custom))
}
