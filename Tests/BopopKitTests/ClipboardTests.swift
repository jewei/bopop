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
    #expect(firstResults.last?.icon == .symbol("trash"))
    #expect(firstResults.last?.keywords == ["clear", "delete"])
    #expect(firstResults.last?.action == .clearClipboardHistory)
    #expect(firstResults.last?.secondaryActions == [])
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
    // No secondary copy action: the primary action already is `.copyText`,
    // and ActionRunner.performCopy falls back to the primary action when
    // secondaryActions has no copyText entry of its own.
    #expect(results[0].secondaryActions == [])
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
