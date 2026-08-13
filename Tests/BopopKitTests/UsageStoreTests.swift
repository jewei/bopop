import Foundation
import Testing
@testable import BopopKit

@MainActor
@Test
func usageStoreRecordsHits() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let store = UsageStore(storage: fixture.storage, now: { date })

    store.record("app:foo")
    store.record("app:foo")

    #expect(abs(store.score("app:foo") - 2) < 1e-9)
}

@MainActor
@Test
func usageStoreRollsBackWhenPersistenceFails() throws {
    struct ExpectedFailure: Error {}
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = UsageStore(
        storage: fixture.storage,
        saveEntries: { _ in throw ExpectedFailure() }
    )

    let result = store.record("app:failed")

    #expect(store.score("app:failed") == 0)
    guard case .failure = result else {
        Issue.record("expected persistence failure")
        return
    }
}

@MainActor
@Test func usageStoreReportsSanitizationWriteFailure() throws {
    struct ExpectedFailure: Error {}
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    try fixture.storage.save(
        ["app:invalid": PersistedUsageEntry(hits: 0, lastUsed: Date())],
        version: 1,
        to: fixture.storage.usageFileURL
    )
    let store = UsageStore(
        storage: fixture.storage,
        saveEntries: { _ in throw ExpectedFailure() }
    )

    #expect(store.persistenceError != nil)
}

@MainActor
@Test
func usageStoreDecaysWithFourteenDayHalfLife() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recordedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var currentDate = recordedAt
    let store = UsageStore(storage: fixture.storage, now: { currentDate })

    store.record("app:foo")
    store.record("app:foo")
    currentDate = recordedAt.addingTimeInterval(14 * 86_400)
    #expect(abs(store.score("app:foo") - 1) < 1e-9)

    currentDate = recordedAt.addingTimeInterval(28 * 86_400)
    #expect(abs(store.score("app:foo") - 0.5) < 1e-9)
}

@MainActor
@Test
func usageStoreReturnsZeroForUnknownID() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let store = UsageStore(storage: fixture.storage)

    #expect(store.score("app:missing") == 0)
}

@MainActor
@Test
func usageStoreEvictsLowestScoreBeyondBound() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    var currentDate = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let store = UsageStore(
        storage: fixture.storage,
        now: { currentDate },
        maxEntries: 3
    )

    store.record("app:oldest")
    currentDate.addTimeInterval(86_400)
    store.record("app:middle")
    currentDate.addTimeInterval(86_400)
    store.record("app:recent")
    currentDate.addTimeInterval(86_400)
    store.record("app:newest")

    #expect(store.score("app:oldest") == 0)
    #expect(store.score("app:middle") > 0)
    #expect(store.score("app:recent") > 0)
    #expect(store.score("app:newest") > 0)
}

@MainActor
@Test
func usageStorePersistsRecords() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    let firstStore = UsageStore(storage: fixture.storage, now: { date })
    firstStore.record("app:foo")

    let secondStore = UsageStore(storage: fixture.storage, now: { date })

    #expect(abs(secondStore.score("app:foo") - 1) < 1e-9)
}

@MainActor
@Test
func usageStoreSanitizesLoadedHitCounts() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    try fixture.storage.save(
        [
            "app:negative": PersistedUsageEntry(hits: -1, lastUsed: date),
            "app:zero": PersistedUsageEntry(hits: 0, lastUsed: date),
            "app:huge": PersistedUsageEntry(hits: Int.max, lastUsed: date)
        ],
        version: 1,
        to: fixture.storage.usageFileURL
    )

    let store = UsageStore(storage: fixture.storage, now: { date })

    #expect(store.score("app:negative") == 0)
    #expect(store.score("app:zero") == 0)
    #expect(store.score("app:huge") == 999)
    store.record("app:huge")
    #expect(store.score("app:huge") == 999)
}

@MainActor
@Test
func usageStoreEvictsLowestScoreWhileLoading() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    try fixture.storage.save(
        [
            "app:low": PersistedUsageEntry(hits: 1, lastUsed: date),
            "app:middle": PersistedUsageEntry(hits: 2, lastUsed: date),
            "app:high": PersistedUsageEntry(hits: 3, lastUsed: date)
        ],
        version: 1,
        to: fixture.storage.usageFileURL
    )

    let store = UsageStore(storage: fixture.storage, now: { date }, maxEntries: 2)

    #expect(store.score("app:low") == 0)
    #expect(store.score("app:middle") == 2)
    #expect(store.score("app:high") == 3)
}

/// Sanitizing only in memory would leave the rejected rows on disk, so a later
/// launch with a bigger cap — or a plain reopen — would rank them again.
@MainActor
@Test
func usageStorePersistsSanitizedTableForLaterLaunches() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
    try fixture.storage.save(
        [
            "app:bogus": PersistedUsageEntry(hits: 0, lastUsed: date),
            "app:low": PersistedUsageEntry(hits: 1, lastUsed: date),
            "app:high": PersistedUsageEntry(hits: 3, lastUsed: date)
        ],
        version: 1,
        to: fixture.storage.usageFileURL
    )

    _ = UsageStore(storage: fixture.storage, now: { date }, maxEntries: 1)
    let nextLaunch = UsageStore(storage: fixture.storage, now: { date }, maxEntries: 500)

    #expect(nextLaunch.score("app:bogus") == 0)
    #expect(nextLaunch.score("app:low") == 0)
    #expect(nextLaunch.score("app:high") == 3)
}

@MainActor
@Test
func usageStoreDoesNotBoostScoresAfterClockMovesBackward() throws {
    let fixture = try makeTestStorage()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recordedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var currentDate = recordedAt
    let store = UsageStore(storage: fixture.storage, now: { currentDate })
    store.record("app:foo")

    currentDate = recordedAt.addingTimeInterval(-14 * 86_400)

    #expect(store.score("app:foo") == 1)
    #expect(store.scores(for: ["app:foo"])["app:foo"] == 1)
}

private struct PersistedUsageEntry: Codable {
    let hits: Int
    let lastUsed: Date
}
