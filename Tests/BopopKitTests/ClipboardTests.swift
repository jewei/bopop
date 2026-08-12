import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func clipboardStoreDeduplicatesOnlyConsecutiveEntries() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("A")
    store.add("A")
    #expect(store.entries.map(\.text) == ["A"])

    store.add("B")
    store.add("A")
    #expect(store.entries.map(\.text) == ["A", "B", "A"])
    #expect(store.entries.map(\.capturedAt) == [
        Date(timeIntervalSince1970: 1_002),
        Date(timeIntervalSince1970: 1_001),
        Date(timeIntervalSince1970: 1_000)
    ])
}

@MainActor
@Test
func clipboardStoreEvictsOldestEntries() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage, limit: 3)

    for text in ["A", "B", "C", "D"] {
        store.add(text)
    }

    #expect(store.entries.map(\.text) == ["D", "C", "B"])
}

// Boundary values below (100 s / 130 s against a 120 s window) match the
// narrowed PasteboardWatcher.upstreamClearScrubWindow (600 s → 120 s, Task 6):
// the scrub exists for sensitive managers like Apple Passwords that clear
// ~90 s after copy, not for arbitrary same-session clears many minutes later.

@MainActor
@Test
func clipboardStoreForgetsEveryRecentCaptureOnUpstreamClear() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("older")
    currentDate = Date(timeIntervalSince1970: 1_010)
    store.add("secret")
    currentDate = Date(timeIntervalSince1970: 1_110) // 100 s after "secret"

    // Both are inside the window, so both go. Scrubbing only the newest left
    // an earlier password in history for good when two were copied in a row.
    store.forgetCaptures(within: 120)
    #expect(store.entries.isEmpty)

    let reloaded = ClipboardStore(storage: fixture.storage)
    #expect(reloaded.entries.isEmpty)
}

/// The window still bounds it: a capture older than the window survives a
/// clear it had nothing to do with.
@MainActor
@Test
func clipboardStoreKeepsCapturesOlderThanTheWindow() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("long ago")
    currentDate = Date(timeIntervalSince1970: 1_200)
    store.add("just now")
    currentDate = Date(timeIntervalSince1970: 1_260) // 60s after "just now"

    store.forgetCaptures(within: 120)
    #expect(store.entries.map(\.text) == ["long ago"])
}

@MainActor
@Test
func clipboardStoreKeepsNewestWhenClearArrivesLate() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("kept")
    currentDate = Date(timeIntervalSince1970: 1_130) // 130 s after "kept"

    store.forgetCaptures(within: 120)
    #expect(store.entries.map(\.text) == ["kept"])

    store.clear()
    store.forgetCaptures(within: 120)
    #expect(store.entries.isEmpty)
}

@Test
func capturePolicyDetectsUpstreamClear() {
    #expect(ClipboardCapturePolicy.isUpstreamClear(types: []))
    #expect(!ClipboardCapturePolicy.isUpstreamClear(types: ["public.utf8-plain-text"]))
    #expect(!ClipboardCapturePolicy.isUpstreamClear(types: ["public.png"]))
}

@MainActor
@Test
func clipboardStoreEnforcesUTF8SizeLimit() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage)

    store.add(String(repeating: "x", count: 100_001))
    #expect(store.entries.isEmpty)

    let maximumText = String(repeating: "x", count: 100_000)
    store.add(maximumText)
    #expect(store.entries.map(\.text) == [maximumText])
}

@MainActor
@Test
func clipboardStoreSkipsEmptyAndWhitespaceOnlyText() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage)

    store.add("")
    store.add(" \t\n\r")

    #expect(store.entries.isEmpty)
}

@MainActor
@Test
func clipboardStorePersistsWithPrivatePermissions() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    let firstStore = ClipboardStore(
        storage: fixture.storage,
        now: { capturedAt }
    )
    firstStore.add("persisted")

    let secondStore = ClipboardStore(storage: fixture.storage)

    #expect(secondStore.entries.count == 1)
    #expect(secondStore.entries.first?.text == "persisted")
    #expect(secondStore.entries.first?.capturedAt == capturedAt)
    #expect(secondStore.entries.first?.pinnedAt == nil)
    // The id is the store's primary key, so it has to survive the round trip.
    #expect(secondStore.entries.first?.id == firstStore.entries.first?.id)
    #expect(try clipboardPermissions(at: fixture.storage.clipboardFileURL) == 0o600)
}

@MainActor
@Test
func clipboardStoreSetLimitTrimsAndPersists() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage, limit: 5)
    for text in ["A", "B", "C", "D", "E"] {
        store.add(text)
    }

    store.setLimit(2)

    #expect(store.entries.map(\.text) == ["E", "D"])
    let reloadedStore = ClipboardStore(storage: fixture.storage, limit: 5)
    #expect(reloadedStore.entries.map(\.text) == ["E", "D"])
}

@MainActor
@Test
func clipboardStoreClearEmptiesAndPersistsWithPrivatePermissions() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage)
    store.add("private clipboard text")

    store.clear()

    #expect(store.entries.isEmpty)
    #expect(FileManager.default.fileExists(atPath: fixture.storage.clipboardFileURL.path))
    let reloadedStore = ClipboardStore(storage: fixture.storage)
    #expect(reloadedStore.entries.isEmpty)
    #expect(try clipboardPermissions(at: fixture.storage.clipboardFileURL) == 0o600)
}

@MainActor
@Test
func clipboardStorePinSortsAboveUnpinnedMostRecentFirst() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("A")
    store.add("B")
    store.add("C")
    store.pin(id: store.id(of: "A"))
    store.pin(id: store.id(of: "B")) // more recent pin

    #expect(store.entries.map(\.text) == ["B", "A", "C"])
    #expect(store.entries[0].pinnedAt != nil)
    #expect(store.entries[1].pinnedAt != nil)
    #expect(store.entries[2].pinnedAt == nil)
}

@MainActor
@Test
func clipboardStoreClearKeepsPinnedEntries() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("keep")
    store.add("drop")
    store.pin(id: store.id(of: "keep"))
    store.clear()

    #expect(store.entries.map(\.text) == ["keep"])
    #expect(store.entries[0].pinnedAt != nil)

    let reloaded = ClipboardStore(storage: fixture.storage)
    #expect(reloaded.entries.map(\.text) == ["keep"])
    #expect(reloaded.entries[0].pinnedAt != nil)
}

@MainActor
@Test
func clipboardStoreTrimExemptsPinnedEntries() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage, limit: 2) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("old-pin")
    store.pin(id: store.id(of: "old-pin"))
    store.add("u1")
    store.add("u2")
    store.add("u3")

    #expect(store.entries.map(\.text) == ["old-pin", "u3", "u2"])
    #expect(store.entries.filter { $0.pinnedAt != nil }.count == 1)
    #expect(store.entries.filter { $0.pinnedAt == nil }.count == 2)
}

@MainActor
@Test
func clipboardStoreAddWithPinsDedupsAgainstNewestCapture() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("pinned")
    store.add("fresh")
    store.pin(id: store.id(of: "pinned"))
    #expect(store.entries.map(\.text) == ["pinned", "fresh"])

    store.add("fresh")
    #expect(store.entries.map(\.text) == ["pinned", "fresh"])

    store.add("newer")
    #expect(store.entries.map(\.text) == ["pinned", "newer", "fresh"])
}

/// Activating a pin copies its text, which PasteboardWatcher reads straight
/// back — the pin must not sprout an unpinned twin of itself.
@MainActor
@Test
func clipboardStoreAddSkipsTextThatIsAlreadyPinned() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("deploy-key")
    store.pin(id: store.id(of: "deploy-key"))
    store.add("foo")
    // "foo" is now the newest capture, so the consecutive-dedup guard misses.
    store.add("deploy-key")

    #expect(store.entries.map(\.text) == ["deploy-key", "foo"])
}

@MainActor
@Test
func clipboardStoreScrubSkipsPinnedEntries() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("older")
    currentDate = Date(timeIntervalSince1970: 1_010)
    store.add("kept-by-pin")
    store.pin(id: store.id(of: "kept-by-pin"))
    currentDate = Date(timeIntervalSince1970: 1_020)
    store.add("secret")
    currentDate = Date(timeIntervalSince1970: 1_110)

    // Everything unpinned inside the window goes, but an explicit keep
    // outranks a heuristic that can't identify who cleared the pasteboard.
    store.forgetCaptures(within: 120)
    #expect(store.entries.map(\.text) == ["kept-by-pin"])

    let reloaded = ClipboardStore(storage: fixture.storage)
    #expect(reloaded.entries.map(\.text) == ["kept-by-pin"])
}

@MainActor
@Test
func clipboardStoreLoadKeepsPinsBeyondUnpinnedLimit() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let writer = ClipboardStore(storage: fixture.storage, limit: 10) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }
    writer.add("pin-a")
    writer.add("pin-b")
    writer.add("u1")
    writer.add("u2")
    writer.add("u3")
    writer.pin(id: writer.id(of: "pin-a"))
    writer.pin(id: writer.id(of: "pin-b"))

    let reader = ClipboardStore(storage: fixture.storage, limit: 2)
    #expect(reader.entries.filter { $0.pinnedAt != nil }.map(\.text) == ["pin-b", "pin-a"])
    #expect(reader.entries.filter { $0.pinnedAt == nil }.count == 2)
}

@MainActor
@Test
func clipboardStoreUnpinRestoresCaptureOrder() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("A")
    store.add("B")
    store.pin(id: store.id(of: "A"))
    store.unpin(id: store.id(of: "A"))

    #expect(store.entries.map(\.text) == ["B", "A"])
    #expect(store.entries.allSatisfy { $0.pinnedAt == nil })
}

/// Unpinning returns an entry to the unpinned pool, which can push that pool
/// past `limit` — every other mutation trims, and this one used to skip it.
@MainActor
@Test
func clipboardStoreUnpinTrimsBackToLimit() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage, limit: 2) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    store.add("pin-a")
    store.add("pin-b")
    store.pin(id: store.id(of: "pin-a"))
    store.pin(id: store.id(of: "pin-b"))
    store.add("u1")
    store.add("u2")
    #expect(store.entries.count == 4)

    store.unpin(id: store.id(of: "pin-a"))

    // pin-a rejoins the unpinned tail as the oldest of three; limit is 2.
    #expect(store.entries.map(\.text) == ["pin-b", "u2", "u1"])
    let reloaded = ClipboardStore(storage: fixture.storage, limit: 2)
    #expect(reloaded.entries.map(\.text) == ["pin-b", "u2", "u1"])
}

/// Pins are exempt from `limit`, so an unbounded pin count would make the
/// store, the file, and the per-keystroke provider work grow forever.
@MainActor
@Test
func clipboardStoreDemotesOldestPinBeyondPinCap() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage, limit: 500) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }

    let cap = ClipboardStore.maximumPinnedEntries
    for index in 0...cap {
        store.add("entry-\(index)")
    }
    for index in 0...cap {
        store.pin(id: store.id(of: "entry-\(index)"))
    }

    #expect(store.entries.filter { $0.pinnedAt != nil }.count == cap)
    // The demoted pin is the least recently pinned one — entry-0 — and it
    // stays in history rather than being deleted.
    #expect(store.entries.last?.text == "entry-0")
    #expect(store.entries.last?.pinnedAt == nil)
    #expect(store.entries.count == cap + 1)
}

/// Load runs the same cap policy as the mutations rather than a second copy
/// of it, so a file written under a looser cap converges on reload.
@MainActor
@Test
func clipboardStoreLoadAppliesBothCaps() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let writer = ClipboardStore(storage: fixture.storage, limit: 10) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }
    for text in ["p1", "u1", "u2", "u3"] {
        writer.add(text)
    }
    writer.pin(id: writer.id(of: "p1"))

    let reader = ClipboardStore(storage: fixture.storage, limit: 1)

    #expect(reader.entries.map(\.text) == ["p1", "u3"])
}

@MainActor
@Test
func clipboardProviderReturnsOnlyClipboardModeEntries() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }
    store.add("older")
    store.add("newer")
    let provider = ClipboardProvider(store: store)

    let generalResults = try await provider.results(
        for: ParsedQuery(mode: .general, term: "")
    )
    let firstResults = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )
    let secondResults = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(generalResults.isEmpty)
    #expect(firstResults.map(\.title) == [
        "newer",
        "older",
        "Clear Clipboard History"
    ])
    #expect(firstResults.map(\.id) == [
        "clip:\(store.id(of: "newer").uuidString)",
        "clip:\(store.id(of: "older").uuidString)",
        "clip:clear"
    ])
    #expect(secondResults.map(\.id) == firstResults.map(\.id))
    #expect(firstResults.map(\.sortHint) == [0, 1, 2])
    #expect(firstResults.map(\.badge) == ["Clipboard", "Clipboard", "Clipboard"])
    #expect(firstResults[0].icon == .symbol("doc.on.clipboard"))
    #expect(firstResults[0].secondaryActions == [
        .pinClipboard(store.id(of: "newer"))
    ])
    #expect(firstResults[1].secondaryActions == [
        .pinClipboard(store.id(of: "older"))
    ])
    #expect(firstResults.last?.icon == .symbol("trash"))
    #expect(firstResults.last?.subtitle == nil)
    #expect(firstResults.last?.keywords == ["clear", "delete"])
    #expect(firstResults.last?.action == .clearClipboardHistory)
    #expect(firstResults.last?.secondaryActions == [])
}

@MainActor
@Test
func clipboardProviderShowsPinIconAndUnpinActionForPinned() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }
    store.add("older")
    store.add("newer")
    store.pin(id: store.id(of: "older"))
    let provider = ClipboardProvider(store: store)

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(results.map(\.title) == ["older", "newer", "Clear Clipboard History"])
    #expect(results[0].icon == .symbol("pin.fill"))
    #expect(results[0].secondaryActions == [
        .unpinClipboard(store.id(of: "older"))
    ])
    #expect(results[1].icon == .symbol("doc.on.clipboard"))
    // Clear keeps pins, so the row says what it will leave behind.
    #expect(results.last?.subtitle == "Keeps 1 pinned item")
}

/// With nothing left for Clear to drop, offering it would be a row that
/// hides the palette and changes nothing.
@MainActor
@Test
func clipboardProviderOmitsClearRowWhenEveryEntryIsPinned() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) {
        defer { currentDate.addTimeInterval(1) }
        return currentDate
    }
    store.add("a")
    store.add("b")
    store.pin(id: store.id(of: "a"))
    store.pin(id: store.id(of: "b"))
    let provider = ClipboardProvider(store: store)

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(results.map(\.title) == ["b", "a"])
}

@MainActor
@Test
func clipboardStoreLoadsLegacyEntriesWithoutPinnedAt() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let capturedAt = Date(timeIntervalSince1970: 1_000)
    struct LegacyEntry: Codable {
        let text: String
        let capturedAt: Date
    }
    struct LegacyEnvelope: Codable {
        let version: Int
        let payload: [LegacyEntry]
    }
    let data = try JSONEncoder().encode(
        LegacyEnvelope(
            version: 1,
            payload: [LegacyEntry(text: "legacy", capturedAt: capturedAt)]
        )
    )
    try data.write(to: fixture.storage.clipboardFileURL)

    let store = ClipboardStore(storage: fixture.storage)
    #expect(store.entries.count == 1)
    #expect(store.entries.first?.text == "legacy")
    #expect(store.entries.first?.capturedAt == capturedAt)
    #expect(store.entries.first?.pinnedAt == nil)
}

/// `id` was added after v1 shipped. Bumping the storage version quarantines
/// the file (see `Storage.load`), so pre-`id` entries must decode in place
/// with a freshly minted one instead of costing the user their history.
@MainActor
@Test
func clipboardStoreLoadsLegacyEntriesWithoutIDAndKeepsThemAddressable() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    struct LegacyEntry: Codable {
        let text: String
        let capturedAt: Date
        let pinnedAt: Date?
    }
    struct LegacyEnvelope: Codable {
        let version: Int
        let payload: [LegacyEntry]
    }
    let data = try JSONEncoder().encode(
        LegacyEnvelope(
            version: 1,
            payload: [
                LegacyEntry(
                    text: "legacy-pin",
                    capturedAt: Date(timeIntervalSince1970: 1_000),
                    pinnedAt: Date(timeIntervalSince1970: 1_500)
                ),
                LegacyEntry(
                    text: "legacy-plain",
                    capturedAt: Date(timeIntervalSince1970: 1_001),
                    pinnedAt: nil
                )
            ]
        )
    )
    try data.write(to: fixture.storage.clipboardFileURL)

    let store = ClipboardStore(storage: fixture.storage)
    #expect(store.entries.map(\.text) == ["legacy-pin", "legacy-plain"])
    #expect(Set(store.entries.map(\.id)).count == 2)

    store.unpin(id: store.id(of: "legacy-pin"))
    #expect(store.entries.allSatisfy { $0.pinnedAt == nil })
}

@MainActor
@Test
func clipboardProviderReturnsNoClearCommandForEmptyStore() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let provider = ClipboardProvider(
        store: ClipboardStore(storage: fixture.storage)
    )

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(results.isEmpty)
}

@MainActor
@Test
func clipboardProviderBuildsTruncatedFirstLineTitles() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = ClipboardStore(storage: fixture.storage)
    store.add(String(repeating: "x", count: 100))
    store.add("line1\nline2")
    let provider = ClipboardProvider(store: store)

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(results[0].title == "line1")
    #expect(results[1].title == String(repeating: "x", count: 60) + "…")
}

@MainActor
@Test
func clipboardProviderCapsSearchKeywordsButCopiesFullText() async throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let text = String(repeating: "x", count: 2_000)
    let store = ClipboardStore(storage: fixture.storage)
    store.add(text)
    let provider = ClipboardProvider(store: store)

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "needle")
    )

    #expect(results[0].keywords == [String(repeating: "x", count: 1_000)])
    #expect(results[0].action == .copyText(text))
    #expect(results[0].secondaryActions.count == 1)
    if case .pinClipboard = results[0].secondaryActions[0] {
        // expected
    } else {
        Issue.record("expected pinClipboard secondary action")
    }
}

@Test
func clipboardCapturePolicyRejectsConcealedType() {
    #expect(!ClipboardCapturePolicy.shouldCapture(
        types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"],
        frontmostBundleID: nil,
        denied: []
    ))
}

@Test
func clipboardCapturePolicyRejectsTransientType() {
    #expect(!ClipboardCapturePolicy.shouldCapture(
        types: ["org.nspasteboard.TransientType"],
        frontmostBundleID: nil,
        denied: []
    ))
}

@Test
func clipboardCapturePolicyRejectsDeniedFrontmostApp() {
    #expect(!ClipboardCapturePolicy.shouldCapture(
        types: ["public.utf8-plain-text"],
        frontmostBundleID: "com.apple.Passwords",
        denied: ["com.apple.Passwords"]
    ))
}

@Test
func clipboardCapturePolicyAllowsNilFrontmostApp() {
    #expect(ClipboardCapturePolicy.shouldCapture(
        types: ["public.utf8-plain-text"],
        frontmostBundleID: nil,
        denied: ["com.apple.Passwords"]
    ))
}

@Test
func clipboardCapturePolicyAllowsNormalCopy() {
    #expect(ClipboardCapturePolicy.shouldCapture(
        types: ["public.utf8-plain-text"],
        frontmostBundleID: "com.apple.TextEdit",
        denied: ["com.apple.Passwords"]
    ))
}

private func clipboardPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

private extension ClipboardStore {
    /// The store keys entries by an opaque `ClipboardEntry.id`; these tests
    /// know them by their text.
    @MainActor
    func id(of text: String) -> UUID {
        guard let entry = entries.first(where: { $0.text == text }) else {
            fatalError("no clipboard entry with text \(text)")
        }
        return entry.id
    }
}

/// Apple's own marker for autofill/password/OTP copies. A clip carrying only
/// this one used to be captured and written to disk like any other.
@Test
func clipboardCapturePolicyRejectsAppleSensitiveMarker() {
    #expect(!ClipboardCapturePolicy.shouldCapture(
        types: ["public.utf8-plain-text", "com.apple.is-sensitive"],
        frontmostBundleID: "com.apple.Safari",
        denied: []
    ))
    // All three markers live in one set, consulted from one place.
    #expect(ClipboardCapturePolicy.sensitiveTypes.count == 3)
    for marker in ClipboardCapturePolicy.sensitiveTypes {
        #expect(!ClipboardCapturePolicy.shouldCapture(
            types: ["public.utf8-plain-text", marker],
            frontmostBundleID: nil,
            denied: []
        ), "\(marker) must suppress capture")
    }
}
