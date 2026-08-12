import AppKit
import Foundation
import Testing
@testable import Bopop
@testable import BopopKit

private struct Fixture {
    let root: URL
    let store: ClipboardStore
    let pasteboard: NSPasteboard
}

@MainActor
private func makeFixture(
    now: @escaping () -> Date = Date.init
) throws -> Fixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("bopop-watcher-\(UUID().uuidString)", isDirectory: true)
    let storage = Storage(baseDirectory: root)
    try storage.ensureDirectories()
    return Fixture(
        root: root,
        store: ClipboardStore(storage: storage, now: now),
        pasteboard: NSPasteboard(name: .init("com.oneone.bopop.tests.\(UUID().uuidString)"))
    )
}

/// Deliberately not `start()`ed: these drive `pollPasteboard()` directly, so
/// there's no run-loop timer to schedule, wait on, or leak into other tests.
/// `lastChangeCount` begins at 0 and every copy below bumps it, so the first
/// poll always sees a change.
@MainActor
private func makeWatcher(
    _ fixture: Fixture,
    frontmost: String? = "com.apple.TextEdit"
) -> PasteboardWatcher {
    PasteboardWatcher(
        store: fixture.store,
        pasteboard: fixture.pasteboard,
        deniedSourceBundleIDs: PasteboardWatcher.defaultDeniedSources,
        frontmostBundleID: { frontmost }
    )
}

@MainActor
@Test
func watcherCapturesPlainTextCopy() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture)

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("hello", forType: .string)
    watcher.pollPasteboard()

    #expect(fixture.store.entries.map(\.text) == ["hello"])
}

/// An unchanged changeCount must not re-capture — otherwise every 0.5 s tick
/// would append the same clip again.
@MainActor
@Test
func watcherIgnoresPollsWithNoPasteboardChange() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture)

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("once", forType: .string)
    watcher.pollPasteboard()
    watcher.pollPasteboard()
    watcher.pollPasteboard()

    #expect(fixture.store.entries.map(\.text) == ["once"])
}

/// Apple Passwords sets no pasteboard marker at all, so the frontmost-app
/// heuristic is the only thing keeping its copies out of history.
@MainActor
@Test
func watcherSkipsCopyFromDeniedFrontmostApp() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture, frontmost: "com.apple.Passwords")

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("hunter2", forType: .string)
    watcher.pollPasteboard()

    #expect(fixture.store.entries.isEmpty)
}

@MainActor
@Test
func watcherSkipsConcealedAndTransientCopies() throws {
    for markerType in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let watcher = makeWatcher(fixture)

        fixture.pasteboard.clearContents()
        fixture.pasteboard.setString("secret", forType: .string)
        fixture.pasteboard.setString("", forType: .init(markerType))
        watcher.pollPasteboard()

        #expect(fixture.store.entries.isEmpty, "\(markerType) should suppress capture")
    }
}

/// A bare clearContents (zero types) is the sensitive-clear signal: scrub the
/// newest unpinned capture if it is recent enough.
@MainActor
@Test
func watcherScrubsRecentCaptureOnUpstreamClear() throws {
    nonisolated(unsafe) var currentDate = Date(timeIntervalSince1970: 1_000)
    let fixture = try makeFixture(now: { currentDate })
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture)

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("secret", forType: .string)
    watcher.pollPasteboard()
    #expect(fixture.store.entries.map(\.text) == ["secret"])

    // 30 s later, the source wipes the pasteboard with no types at all.
    currentDate = Date(timeIntervalSince1970: 1_030)
    fixture.pasteboard.clearContents()
    watcher.pollPasteboard()

    #expect(fixture.store.entries.isEmpty)
}

/// The window exists so an unrelated app's clear minutes later can't delete
/// history it had nothing to do with.
@MainActor
@Test
func watcherKeepsCaptureWhenUpstreamClearArrivesAfterWindow() throws {
    nonisolated(unsafe) var currentDate = Date(timeIntervalSince1970: 1_000)
    let fixture = try makeFixture(now: { currentDate })
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture)

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("keep me", forType: .string)
    watcher.pollPasteboard()

    currentDate = Date(timeIntervalSince1970: 1_000 + PasteboardWatcher.upstreamClearScrubWindow + 10)
    fixture.pasteboard.clearContents()
    watcher.pollPasteboard()

    #expect(fixture.store.entries.map(\.text) == ["keep me"])
}

@MainActor
@Test
func watcherPausesAndRebaselinesAcrossInactiveSession() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let center = NotificationCenter()
    let watcher = PasteboardWatcher(
        store: fixture.store,
        pasteboard: fixture.pasteboard,
        interval: 3_600,
        workspaceNotificationCenter: center,
        frontmostBundleID: { "com.apple.TextEdit" }
    )
    watcher.start()
    defer { watcher.stop() }

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("before", forType: .string)
    watcher.pollPasteboard()

    center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("inactive", forType: .string)
    watcher.pollPasteboard()

    center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    watcher.pollPasteboard()

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("after", forType: .string)
    watcher.pollPasteboard()

    #expect(fixture.store.entries.map(\.text) == ["after", "before"])
}

@MainActor
@Test
func watcherDoesNotScrubHistoryForInactiveSessionClear() throws {
    let fixture = try makeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let center = NotificationCenter()
    let watcher = PasteboardWatcher(
        store: fixture.store,
        pasteboard: fixture.pasteboard,
        interval: 3_600,
        workspaceNotificationCenter: center,
        frontmostBundleID: { "com.apple.TextEdit" }
    )
    watcher.start()
    defer { watcher.stop() }

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("keep", forType: .string)
    watcher.pollPasteboard()

    center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    fixture.pasteboard.clearContents()
    watcher.pollPasteboard()
    center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
    watcher.pollPasteboard()

    #expect(fixture.store.entries.map(\.text) == ["keep"])
}

/// Two passwords copied in succession, then one upstream clear.
///
/// Reported from a manual QA pass: "i copied 2 passwords, 1 is gone, another 1
/// stays". Apple Passwords schedules its wipe per copy, but the second copy
/// replaces the first on the pasteboard, so only one wipe actually lands — and
/// a single wipe scrubs a single entry.
@MainActor
@Test
func watcherScrubsEveryRecentCaptureOnOneUpstreamClear() throws {
    nonisolated(unsafe) var currentDate = Date(timeIntervalSince1970: 1_000)
    let fixture = try makeFixture(now: { currentDate })
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let watcher = makeWatcher(fixture)

    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("first password", forType: .string)
    watcher.pollPasteboard()

    currentDate = Date(timeIntervalSince1970: 1_010)
    fixture.pasteboard.clearContents()
    fixture.pasteboard.setString("second password", forType: .string)
    watcher.pollPasteboard()
    #expect(fixture.store.entries.count == 2)

    // One wipe, 60s after the first copy — both are inside the 120s window.
    currentDate = Date(timeIntervalSince1970: 1_060)
    fixture.pasteboard.clearContents()
    watcher.pollPasteboard()

    #expect(
        fixture.store.entries.map(\.text) == [],
        "a password left behind by the scrub stays in history for good"
    )
}
