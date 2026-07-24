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
func clipboardStoreForgetsRecentNewestOnUpstreamClear() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("older")
    currentDate = Date(timeIntervalSince1970: 1_010)
    store.add("secret")
    currentDate = Date(timeIntervalSince1970: 1_110) // 100 s after "secret"

    store.forgetNewest(ifCapturedWithin: 120)
    #expect(store.entries.map(\.text) == ["older"])

    let reloaded = ClipboardStore(storage: fixture.storage)
    #expect(reloaded.entries.map(\.text) == ["older"])
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

    store.forgetNewest(ifCapturedWithin: 120)
    #expect(store.entries.map(\.text) == ["kept"])

    store.clear()
    store.forgetNewest(ifCapturedWithin: 120)
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

    #expect(secondStore.entries == [
        ClipboardEntry(text: "persisted", capturedAt: capturedAt)
    ])
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
    // times: A@1000, B@1001, C@1002; now advances to 1003
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000)) // A
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_001)) // B, more recent pin

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
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
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
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
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
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
    #expect(store.entries.map(\.text) == ["pinned", "fresh"])

    store.add("fresh")
    #expect(store.entries.map(\.text) == ["pinned", "fresh"])

    store.add("newer")
    #expect(store.entries.map(\.text) == ["pinned", "newer", "fresh"])
}

@MainActor
@Test
func clipboardStoreForgetNewestRemovesMaxCapturedEvenIfPinned() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSince1970: 1_000)
    let store = ClipboardStore(storage: fixture.storage) { currentDate }

    store.add("older")
    currentDate = Date(timeIntervalSince1970: 1_010)
    store.add("secret")
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_010))
    currentDate = Date(timeIntervalSince1970: 1_110)

    store.forgetNewest(ifCapturedWithin: 120)
    #expect(store.entries.map(\.text) == ["older"])
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
    writer.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
    writer.pin(capturedAt: Date(timeIntervalSince1970: 1_001))

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
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
    store.unpin(capturedAt: Date(timeIntervalSince1970: 1_000))

    #expect(store.entries.map(\.text) == ["B", "A"])
    #expect(store.entries.allSatisfy { $0.pinnedAt == nil })
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
        "clip:1001.0",
        "clip:1000.0",
        "clip:clear"
    ])
    #expect(secondResults.map(\.id) == firstResults.map(\.id))
    #expect(firstResults.map(\.sortHint) == [0, 1, 2])
    #expect(firstResults.map(\.badge) == ["Clipboard", "Clipboard", "Clipboard"])
    #expect(firstResults[0].icon == .symbol("doc.on.clipboard"))
    #expect(firstResults[0].secondaryActions == [
        .pinClipboard(Date(timeIntervalSince1970: 1_001))
    ])
    #expect(firstResults[1].secondaryActions == [
        .pinClipboard(Date(timeIntervalSince1970: 1_000))
    ])
    #expect(firstResults.last?.icon == .symbol("trash"))
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
    store.pin(capturedAt: Date(timeIntervalSince1970: 1_000))
    let provider = ClipboardProvider(store: store)

    let results = try await provider.results(
        for: ParsedQuery(mode: .clipboard, term: "")
    )

    #expect(results.map(\.title) == ["older", "newer", "Clear Clipboard History"])
    #expect(results[0].icon == .symbol("pin.fill"))
    #expect(results[0].secondaryActions == [
        .unpinClipboard(Date(timeIntervalSince1970: 1_000))
    ])
    #expect(results[1].icon == .symbol("doc.on.clipboard"))
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
    #expect(store.entries == [
        ClipboardEntry(text: "legacy", capturedAt: capturedAt, pinnedAt: nil)
    ])
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
